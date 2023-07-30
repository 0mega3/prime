%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, Denis Khorkin
%%% @doc prime_server
%%%
%%% The prime server is implemented as a gen_server.
%%% Users call us using the API in prime.erl.
%%%
%%% The server works like this:
%%%  * When starting up, the prime_server initializes and waits for requests.
%%%  * Users call us using gen_server:call (sync) or gen_server:cast (async)
%%%    that sends a request to generate uniformly distributed pseudorandom
%%%    numbers(PRNs) according to the uniform distribution function
%%%    F(x) = x, 2 =< x =< N where N is the upper limit of PRNs.
%%%    In addition, PRNs are generated at a frequency of 3000 numbers per second
%%%    (by default) and are queued in Redis (List data structure).
%%%  * As soon as the generator is started, the filter starts taking PRNs
%%%    from the queue, checking that numbers is prime and adding prime numbers
%%%    in Redis (Set data structure).
%%%  * Parameters:
%%%      * N is the upper limit of pseudorandom numbers (aka PrnUpperLimit);
%%%      * RedisHost, RedisPort, RedisDB are connection parameters to Redis;
%%%      * QueueKey is the queue key used by the generator in Redis;
%%%      * ResultSetKey is the set key used by the filter in Redis.
%%% @author Denis Khorkin
%%% @end
%%%-----------------------------------------------------------------------------
-module(prime_server).
-behaviour(gen_server).

-define(APP_INTERVAL, 1000). % one sec., time in milliseconds
-define(NOI, 3000). % number of iterations

%% API
-export([start_link/6, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
          prn_upper_limit :: pos_integer() | undefined,
          host :: string() | undefined,
          port :: integer() | undefined,
          database :: binary() | undefined,
          generator_key :: string() | undefined,
          filter_key::string() | undefined,
          pub_sub :: {pid() | undefined, pid() | undefined},
          tref :: timer:tref() | undefined
 }).

%%
%% API
%%

-spec start_link(PrnUpperLimit::pos_integer(),
                 Host::list(),
                 Port::integer(),
                 Database::integer() | undefined,
                 QueueKey::string(),
                 ResultSetKey::string()) ->
                    {ok, Pid::pid()} | {error, Reason::term()}.
start_link(PrnUpperLimit, Host, Port, Database, QueueKey, ResultSetKey) ->
    gen_server:start_link(?MODULE, [PrnUpperLimit, Host, Port, Database,
                                    QueueKey, ResultSetKey], []).

stop(Pid) ->
    gen_server:call(Pid, stop).

%%%==========================================================================
%%% gen_server callbacks
%%%==========================================================================

init([PrnUpperLimit, Host, Port, Database, QueueKey, ResultSetKey]) ->
    State = #state{prn_upper_limit = PrnUpperLimit,
                   host = Host,
                   port = Port,
                   database = Database,
                   generator_key =  QueueKey,
                   filter_key = ResultSetKey,
                   pub_sub = {undefined, undefined},
                   tref = undefined},
    process_flag(trap_exit, true),
    gen_server:cast(self(), {request, eredis_start}),
    {ok, State}.

handle_call({request, cancel}, _From, State) ->
    do_cancel(State);

handle_call({request, get_res}, _From, State) ->
    do_get_res(State);

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.

handle_cast({request, eredis_start}, #state{host = Host,
                                            port = Port,
                                            database = Database} = State) ->
    {ok, Pub} = eredis:start_link(Host, Port, Database),
    {ok, Sub} = eredis_sub:start_link(Host, Port, ""),
    NewState = State#state{pub_sub = {Pub, Sub}},
    {noreply, NewState};

handle_cast({request, generate}, State) ->
    do_generate(State);

handle_cast(_Msg, State) ->
    {noreply, State}.

%% eredis_sub client messages <<<
handle_info({subscribed, _Channel, From} = Msg, State) ->
    io:format("~p~n", [Msg]),
    eredis_sub:ack_message(From),
    {noreply, State};

handle_info({message, <<"QueueKey">> = _Channel, Msg, From}, State) ->
    do_filter(Msg, From, State);

handle_info({message, _Channel, _Msg, _From}, State) ->
    {noreply, State};
%% >>>

handle_info({'EXIT', _From, normal}, State) ->
    io:format("Bye bye!~n", []),
    {noreply, State};

handle_info(stop, State) ->
    {stop, shutdown, State};

handle_info(_Info, State) ->
    {stop, {unhandled_message, _Info}, State}.

terminate(Reason, _State) ->
    exit(self(), Reason).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%==========================================================================
%%% Internal functions
%%%==========================================================================

-spec do_generate(#state{}) -> {noreply, #state{}}.

%% @doc The generator starts generating and adding pseudorandom numbers
%% to the queue (The QueueKey key is used by the generator by default).
%% The eredis client is used to communicate with Redis.
do_generate(#state{prn_upper_limit = PrnUpperLimit,
                   generator_key = QueueKey,
                   pub_sub = {Pub, Sub}} = State) ->

    %% Make the calling process the controlling process.
    %% The controlling process receives pubsub-related messages.
    %% {message, Channel::binary(), Message::binary(), pid()}
    %% This is sent for each pubsub message received by the client.
    %% In each message, the pid refers to the eredis client process.
    ok = eredis_sub:controlling_process(Sub),
    %% Subscribe to the given channels. Returns immediately.
    %% The result will be delivered to the controlling process as any other
    %% message. Delivers {subscribed, Channel::binary(), pid()}
    ok = eredis_sub:subscribe(Sub, [QueueKey]),

    {ok, TRef} =
    timer:apply_interval(?APP_INTERVAL, erlang, apply,
                         [fun do_generate_helper/3,
                          [PrnUpperLimit, Pub, QueueKey]]),
    NewState = State#state{tref = TRef},
    {noreply, NewState}.

do_generate_helper(PrnUpperLimit, Publisher, Channel) ->
    PRNs = [rand:uniform(PrnUpperLimit) || _ <- lists:seq(1, ?NOI)],
    BinPRNs = unicode:characters_to_binary(PRNs, unicode),
    {ok, _Qty} = eredis:q(Publisher, ["PUBLISH", Channel, BinPRNs]).

-spec do_filter(binary(), pid(), #state{}) -> {noreply, #state{}}.

%% @doc The filter takes a pseudorandom number from the queue,
%% checks that the number is prime and adds it to the redis
%% (Set data structure).
do_filter(Msg, From, #state{filter_key = ResultSetKey,
                            pub_sub = {Pub, _}} = State) ->
    PRNs = unicode:characters_to_list(Msg, unicode),
    Primes = lists:filter(fun(PRN) -> miller_rabin:is_prime(PRN) end, PRNs),
    BinPrimes = unicode:characters_to_binary(Primes, unicode),

    %% Primality tests
    %%
    %% PrimeTest_ = fun(PRNs) ->
    %% lists:filter(fun(PRN) -> miller_rabin:is_prime(PRN) end, PRNs) end.
    %%
    %% PrimeTest = fun(PRNs) ->
    %% Primes = [N || N <- lists:seq(1, 1000), miller_rabin:is_prime(N)],
    %% [PRN || PRN <- PRNs, lists:member(PRN, Primes)] end.
    %%
    %% timer:tc(PrimeTest_, [PRNs]).
    %% timer:tc(PrimeTest, [PRNs]).

    {ok, _Qty} = eredis:q(Pub, ["SADD", ResultSetKey, BinPrimes]),

    %% Acknowledge the receipt of a pubsub message. Each pubsub
    %% message must be acknowledged before the next one is received
    eredis_sub:ack_message(From),
    {noreply, State}.

-spec do_get_res(#state{}) -> {reply, binary(), #state{}}.

%% @doc Requests data from the redis (from the Set data structure) by the key
%% (the ResultSetKey key used to for retrieving by default).
do_get_res(#state{filter_key = ResultSetKey,
              pub_sub    = {Pub, _}} = State) ->
    {ok, BinRes} = eredis:q(Pub, ["SMEMBERS", ResultSetKey]),
    Res = unicode:characters_to_list(BinRes, unicode),
    {reply, Res, State}.

-spec do_cancel(#state{}) -> {reply, any(), #state{}}.

%% @doc Cancels the timer to generate pseudorandom numbers.
do_cancel(#state{pub_sub = {_Pub, _Sub},
                 tref = TRef} = State) ->
    case timer:cancel(TRef) of
        {ok, cancel} ->
            %%ok = eredis:stop(Pub),
            %%ok = eredis_sub:stop(Sub),
            NewState = State#state{tref = undefined},
            {reply, cancelled, NewState};
        {error, Reason} -> {reply, Reason, State}
    end.
