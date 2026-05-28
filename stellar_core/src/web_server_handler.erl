-module(web_server_handler).
-behaviour(cowboy_handler).

-export([init/2]).

handle_request(<<"home">>, _Req, _State) ->
    <<"Welcome">>;
handle_request(<<"random">>, _Req, _State) ->
    RandomNum = rand:uniform(100),
    RandomNumBin = integer_to_binary(RandomNum),
    <<"Random: ", RandomNumBin/binary>>;
handle_request(<<"time">>, _Req, _State) ->
    ServerTime = erlang:system_time(),
    ServerTimeBin = integer_to_binary(ServerTime),
    <<"The server time is: ", ServerTimeBin/binary>>;
handle_request(_, _Req, _State) ->
    <<"Unknown route">>.

init(Req, State) ->
    Path = maps:get(path, State, <<"home">>),
    Res = handle_request(Path, Req, State),
    {ok, Req2} = cowboy_req:reply(200,
        #{<<"content-type">> => <<"text/plain">>},
        Res,
        Req),
    {ok, Req2, State}.
