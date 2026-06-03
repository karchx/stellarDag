%%%-------------------------------------------------------------------
%% @doc stellar_core public API
%% @end
%%%-------------------------------------------------------------------

-module(stellar_core_app).
-behaviour(application).

-export([start/2, stop/1]).
-define(COWBOY_PORT, 8080).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        { '_', [
            {"/ws", ws_handler, []},
            {"/", web_server_handler, #{path => <<"home">>}},
            {"/random", web_server_handler, #{path => <<"random">>}},
            {"/time", web_server_handler, #{path => <<"time">>}}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(http_listener, [{port, ?COWBOY_PORT}], #{env => #{dispatch => Dispatch}}),
    stellar_core_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
