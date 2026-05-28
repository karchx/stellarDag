-module(workflow_fsm).
-behaviour(gen_statem).

%% API
-export([start_link/1, start/1, complete/1, error/1, get_state/1]).

-export([init/1, callback_mode/0, terminate/3]).

-export([queue/3, running/3, retry/3, success/3, failed/3]).

-compile({no_auto_import, [error/1]}).

-include_lib("kernel/include/logger.hrl").

-record(data, {
    id,
    max_retries = 3,
    retries = 0,
    base_backoff = 1000 %miliseconds
}).

start_link(Opts) ->
    gen_statem:start_link(?MODULE, Opts, []).

start(Pid) ->
    gen_statem:cast(Pid, start).

complete(Pid) ->
    gen_statem:cast(Pid, complete).

error(Pid) ->
    gen_statem:cast(Pid, error).

get_state(Pid) ->
    gen_statem:call(Pid, get_state).

callback_mode() ->
    state_functions.

init(Opts) ->
    Data = #data{
        id = proplists:get_value(id, Opts, make_ref()),
        max_retries = proplists:get_value(max_retries, Opts, 3),
        base_backoff = proplists:get_value(base_backoff, Opts, 1000)
    },
    ?LOG_INFO("Job ~p: Initialized in queue", [Data#data.id]),
    {ok, queue, Data}.

terminate(_Reason, State, Data) ->
    ?LOG_INFO("Job ~p: Terminating in state ~p", [Data#data.id, State]),
    ok.

queue(cast, start, Data) ->
    ?LOG_INFO("Job ~p: Transitioning queue -> running", [Data#data.id]),
    {next_state, running, Data};
queue({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, queue}]};
queue(_, _, _) ->
    keep_state_and_data.

running(cast, complete, Data) ->
    ?LOG_INFO("Job ~p: Transitioning running -> success", [Data#data.id]),
    {next_state, success, Data};

running(cast, error, #data{retries = R, max_retries = Max} = _Data) when R >= Max ->
    {keep_state_and_data, [{next_event, internal, max_retries_reached}]};

running(cast, error, #data{retries = R, base_backoff = Base} = Data) ->
    NextRetry = R + 1,
    Timeout = Base * (1 bsl R), % Backoff exp: Base * 2^R
    ?LOG_WARNING("Job ~p Error. Attemp ~p/~p. Timeout ~p ms",
                 [Data#data.id, NextRetry, Data#data.max_retries, Timeout]),
    {next_state, retry, Data#data{retries = NextRetry}, [{state_timeout, Timeout, retry_timeout}]};

running(internal, max_retries_reached, Data) ->
    ?LOG_ERROR("Job ~p: Limit Attemps. Transitioning -> failed", [Data#data.id]),
    {next_state, failed, Data};

running({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, running}]};
running(_, _, _) ->
    keep_state_and_data.

retry(state_timeout, retry_timeout, Data) ->
    ?LOG_INFO("Job ~p: Expire timeout. Transitioning retry -> running", [Data#data.id]),
    {next_state, running, Data};
retry({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, retry}]};
retry(_, _, _) ->
    keep_state_and_data.

success({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, success}]};
success(_, _, _) ->
    keep_state_and_data.

failed({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, failed}]};
failed(_, _, _) ->
    keep_state_and_data.

%% ---- EUNIT Test ----
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

workflow_success_test() ->
    {ok, Pid} = start_link([{id, test1}, {max_retries, 1}, {base_backoff, 10}]),
    ?assertEqual(queue, get_state(Pid)),
    start(Pid),
    timer:sleep(10),
    ?assertEqual(running, get_state(Pid)),
    complete(Pid),
    timer:sleep(10),
    ?assertEqual(success, get_state(Pid)),
    gen_statem:stop(Pid).

workflow_retry_test() ->
    {ok, Pid} = start_link([{id, test2}, {max_retries, 1}, {base_backoff, 50}]),
    start(Pid),
    timer:sleep(10),
    error(Pid),
    timer:sleep(10),
    ?assertEqual(retry, get_state(Pid)),
    timer:sleep(150),
    ?assertEqual(running, get_state(Pid)),
    gen_statem:stop(Pid).

workflow_fail_test() ->
    {ok, Pid} = start_link([{id, test3}, {max_retries, 1}, {base_backoff, 1}]),
    start(Pid),
    timer:sleep(10),
    error(Pid),
    timer:sleep(10),
    error(Pid),
    timer:sleep(10),
    ?assertEqual(failed, get_state(Pid)),
    gen_statem:stop(Pid).

-endif.
