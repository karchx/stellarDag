-module(job_fsm).
-behaviour(gen_statem).

%% API
-export([start_link/1, assign_worker/2, job_finished/2, get_state/1]).

-export([init/1, callback_mode/0, handle_event/4, terminate/3]).

-record(data, {
    job_id,
    payload,
    orchestrator_pid,
    worker_pid = undefined,
    worker_mon = undefined, %ref monitor
    retries = 0,
    max_retries = 3,
    base_backoff = 1000 %miliseconds
}).

start_link(Opts) ->
    gen_statem:start_link(?MODULE, Opts, []).

assign_worker(Pid, WorkerPid) ->
    gen_statem:cast(Pid, {worker_assigned, WorkerPid}).

job_finished(Pid, Result) ->
    gen_statem:cast(Pid, {job_result, Result}).

callback_mode() -> 
    [handle_event_function, state_enter].

get_state(JobId) ->
    case ets:lookup(job_states, JobId) of
        [{JobId, State}] -> {ok, State};
        [] -> {error, not_found}
    end.

init(Opts) ->
    Data = #data{
        job_id = proplists:get_value(job_id, Opts),
        payload = proplists:get_value(payload, Opts),
        orchestrator_pid = proplists:get_value(orchestrator_pid, Opts),
        max_retries = proplists:get_value(max_retries, Opts, 3),
        base_backoff = proplists:get_value(base_backoff, Opts, 1000)
    },
    {ok, ready, Data, [{next_event, internal, request_worker}]}.

handle_event(internal, request_worker, ready, Data) ->
    case worker_pool:request_worker() of
        {ok, WorkerPid} ->
            Ref = erlang:monitor(process, WorkerPid),
            %% Got one immediately: skip the queue state.
            NewData = Data#data{worker_pid = WorkerPid, worker_mon = Ref},
            {next_state, starting, NewData, [{next_event, internal, start_execution}]};
        {error, pool_exhausted} ->
            %% No worker available: park in `queue` and wait for and assign_worker cast.
            %% The orchestrator (or pool) is responsible for calling assign_worker/2
            {next_state, queue, Data}
    end;


handle_event(enter, _OldState, State, Data) ->
    ets:insert(job_states, {Data#data.job_id, State}),
    %% Broadcast all ws
    [Pid ! {job_update, Data#data.job_id, State} || Pid <- pg:get_members(ws_clients)],

    keep_state_and_data;

%% State queue
handle_event(cast, {worker_assigned, WorkerPid}, queue, Data) ->
    Ref = erlang:monitor(process, WorkerPid),
    {next_state, starting, Data#data{worker_pid = WorkerPid, worker_mon = Ref}, 
    [{next_event, internal, start_execution}]};

%% State starting
handle_event(internal, start_execution, starting, Data) ->
    worker_pool:execute(Data#data.worker_pid, Data#data.job_id, Data#data.payload, self()),
    {next_state, active, Data};
%% State active
handle_event(cast, {job_result, success}, active, Data) ->
    erlang:demonitor(Data#data.worker_mon, [flush]),
    notify_orchestrator(Data, success),
    {next_state, finished_success, Data, [{state_timeout, 0, stop_fsm}]};

handle_event(cast, {job_result, error}, active, Data) ->
    erlang:demonitor(Data#data.worker_mon, [flush]),
    NextRetry = Data#data.retries + 1,
    case NextRetry > Data#data.max_retries of
        true ->
            error_logger:error_msg("[job_fsm] Job ~p max retries. Abort ~n", [Data#data.job_id]),
            notify_orchestrator(Data, abort),
            {next_state, abort, Data, [{state_timeout, 0, stop_fsm}]};
        false ->
            Timeout = Data#data.base_backoff * (1 bsl Data#data.retries),
            error_logger:warning_msg("[job_fsm] Job ~p failed, Retry ~p/~p", [Data#data.job_id, NextRetry, Data#data.max_retries]),
            {next_state, retry_delay, Data#data{retries = NextRetry, worker_pid = undefined},
            [{state_timeout, Timeout, backoff_expired}]}
    end;
handle_event(info, {'DOWN', Ref, process, WorkerPid, _Reason}, active, Data = #data{worker_mon = Ref, worker_pid = WorkerPid}) ->
    error_logger:warning_msg("Worker ~p crashed unexpectedly during job ~p~n", [WorkerPid, Data#data.job_id]),
    handle_event(cast, {job_result, error}, active, Data);

%% retry_delay
handle_event(state_timeout, backoff_expired, retry_delay, Data) ->
    {next_state, ready, Data, [{next_event, internal, request_worker}]};
%% off FSM in terminate job
handle_event(state_timeout, stop_fsm, State, Data) when State == finished_success; State == aborted ->
    {stop, normal, Data};
%% Cath-all
handle_event(EventType, EventContent, State, _Data) ->
    error_logger:warning_msg("Unhandled event in ~p: ~p/~p~n", [State, EventType, EventContent]),
    keep_state_and_data.

terminate(_Reason, _State, _Data) ->
    ok.

notify_orchestrator(#data{orchestrator_pid = Pid, job_id = JobId}, Result) ->
    gen_server:cast(Pid, {job_done, JobId, Result}).

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
