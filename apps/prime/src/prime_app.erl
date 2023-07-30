%%%-------------------------------------------------------------------
%% @doc prime public API
%% @end
%%%-------------------------------------------------------------------

-module(prime_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    prime_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
