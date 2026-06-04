-module(ws_handler).
-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2]).

init(Req, State) ->
    {cowboy_websocket, Req, State}.

websocket_init(State) ->
    pg:join(ws_clients, self()),
    {ok, State}.

websocket_handle({text, <<"ping">>}, State) ->
    {reply, {text, <<"pong">>}, State};
websocket_handle({text, Msg}, State) ->
    {reply, {text, <<"Echo: ", Msg/binary>>}, State};
websocket_handle(_Data, State) ->
    {ok, State}.

websocket_info({job_update, JobId, Status}, State) ->
    Data = #{<<"job_id">> => JobId, <<"status">> => Status},
    {reply, {text, json:encode(Data)}, State};

websocket_info(_Info, State) ->
    {ok, State}.

