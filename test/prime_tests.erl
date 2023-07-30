-module(prime_tests).

-include_lib("eunit/include/eunit.hrl").

connect_test() ->
    ?assertMatch({ok, _}, prime:start_link(1000, "127.0.0.1", 6379)),
    ?assertMatch({ok, _}, prime:start_link(1000, "localhost", 6379)).

generate_test() ->
    Res = prime:start_link(1000,"127.0.0.1", 6379),
    ?assertMatch({ok, _}, Res),
    {ok, ServerPid} = Res,
    ServerState = sys:get_state(ServerPid),
    {_, Sub} = erlang:element(8, ServerState),
    %% The first publication of the generator is recognized
    %% on the "QueueKey" channel.
    _Receiver =
    spawn_link(fun() ->
                       eredis_sub:controlling_process(Sub),
                       eredis_sub:subscribe(Sub, [<<"QueueKey">>]),
                       receiver(ServerPid)
               end),
    prime:generate(ServerPid).

receiver(ServerPid) ->
    receive
        {subscribed, _Channel, From} ->
            eredis_sub:ack_message(From),
            erlang:apply(fun receiver/1, [ServerPid]);
        {message, Channel, _Msg, _From} ->
            ?assertEqual(<<"QueueKey">>, Channel),
            ok = prime:stop(ServerPid)
    end.
