-module(mtl_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    io:format("Starting MTL server~n"),
    mtl_sup:start_link().

stop(_State) ->
    ok.
