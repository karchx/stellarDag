-module(job_consumer).
-behaviour(gen_server).

-export([start_link/0, init/1, handle_info/2, handle_call/3, handle_cast/2]).

-define(POLL_INTERVAL, 2000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    erlang:send(self(), poll),
    {ok, #{}}.

handle_info(poll, State) ->
    case db_worker:fetch_and_lock_job() of
        {ok, JobName, Payload, ScheduleId} ->
            PayloadMap = json:decode(Payload),
            {ok, _FsmPid} = job_fsm_sup:start_job([
                {job_id, JobName},
                {payload, PayloadMap},
                {schedule_id, ScheduleId},
                {orchestrator_pid, self()}
            ]),
            erlang:send(self(), poll);
        empty ->
            erlang:send_after(?POLL_INTERVAL, self(), poll);
        {error, Reason} ->
            error_logger:error_msg("[job_consumer] Failed on polling: ~p~n", [Reason]),
            erlang:send_after(?POLL_INTERVAL, self(), poll)
    end,
    {noreply, State};

handle_info(Msg, State) ->
    error_logger:warning_msg("[job_consumer] Unhandled info: ~p~n", [Msg]),
    {noreply, State}.

handle_cast({job_done, JobId, Result, ScheduleId}, State) ->
    error_logger:info_msg("[job_consumer] Job ~p finished with result ~p~n", [JobId, Result]),
    db_worker:mark_job_done(JobId, Result),
    db_worker:job_unlock_dependence(ScheduleId),
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, {error, unsupported}, State}.

