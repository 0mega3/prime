%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, Denis Khorkin
%%% @doc ___      _             ____
%%%     / _ \____(_)_ _  ___   / __/__ _____  _____ ____
%%%    / ___/ __/ /  ' \/ -_) _\ \/ -_) __/ |/ / -_) __/
%%%   /_/  /_/ /_/_/_/_/\__/ /___/\__/_/  |___/\__/_/
%%%
%%% @author Denis Khorkin
%%% @end
%%%-----------------------------------------------------------------------------
-module(prime).

%% Uniformly distributed pseudorandom numbers are generated according to
%% the uniform distribution function F(x) = x, 2 =< x =< N
%% where N is the upper limit of pseudorandom numbers (aka PrnUpperLimit)
-define(PRN_UPPER_LIMIT, 1000).
%% The queue key that is used by the generator in Redis
-define(GENERATOR_KEY, "QueueKey").
%% The set key that is used by the filter in Redis
-define(FILTER_KEY, "ResultSetKey").
%% Localhost has the IP address 127.0.0.1, which refers back to
%% your own computer
-define(LOCALHOST, "127.0.0.1").
%% By default, the redis runs of port 6379
-define(PORT, 6379).
%% Default timeout for calls to the client gen_server
%% Specified in http://www.erlang.org/doc/man/gen_server.html#call-3
-define(TIMEOUT, 5000).

-export([start_link/0, start_link/1, start_link/3, start_link/4, start_link/6,
         stop/1, generate/1, cancel/1, get_res/1]).

%% Type of gen_server process id
-type server() :: pid() |
                  atom() |
                  {atom(),atom()} |
                  {global,term()} |
                  {via,atom(),term()}.

%%
%% PUBLIC API
%%

start_link() ->
    start_link(?PRN_UPPER_LIMIT, ?LOCALHOST, ?PORT, 0, ?GENERATOR_KEY, ?FILTER_KEY).

start_link(PrnUpperLimit) ->
    start_link(PrnUpperLimit, ?LOCALHOST, ?PORT, 0, ?GENERATOR_KEY, ?FILTER_KEY).

start_link(PrnUpperLimit, Host, Port) ->
     start_link(PrnUpperLimit, Host, Port, 0, ?GENERATOR_KEY, ?FILTER_KEY).

start_link(PrnUpperLimit, Host, Port, Database) ->
     start_link(PrnUpperLimit, Host, Port, Database, ?GENERATOR_KEY, ?FILTER_KEY).

start_link(PrnUpperLimit, Host, Port, Database, QueueKey, ResultSetKey) when
      is_integer(PrnUpperLimit) andalso PrnUpperLimit > 0,
      is_list(Host),
      is_integer(Port),
      is_integer(Database) orelse Database == undefined,
      is_list(QueueKey),
      is_list(ResultSetKey)->
    prime_server:start_link(PrnUpperLimit, Host, Port, Database, QueueKey, ResultSetKey).

stop(Server) ->
    prime_server:stop(Server).

generate(Server) ->
    q_async(Server, generate).

cancel(Server) ->
    q_sync(Server, cancel).

get_res(Server) ->
    q_sync(Server, get_res).

-spec q_sync(Server:: server(), Command::any()) ->
    {ok, any()} | {error, Reason::any()}.
%% @doc Executes the given command and waits until a reply arrives
%% or a timeout occurs.
q_sync(Server, Command) ->
    q_sync(Server, Command, ?TIMEOUT).

q_sync(Server, Command, Timeout) ->
    gen_server:call(Server, _Request = {request, Command}, Timeout).

-spec q_async(Server::server(), Command::any()) -> ok.
%% @doc Executes the command and returns ok immediately.
%% @see q_sync/2
q_async(Server, Command) ->
    gen_server:cast(Server, _Request = {request, Command}).
