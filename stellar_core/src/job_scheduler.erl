-module(job_scheduler).
-behaviour(gen_server).

-export([start_link/0, add_schedule_job/3, execute_now/1, execute_once/1, active_job/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_schedule_job(JobName, Payload, CronExpr) ->
    gen_server:call(?MODULE, {schedule, JobName, Payload, CronExpr}).

active_job(JobName) ->
    gen_server:cast(?MODULE, {active_job, JobName}).

execute_now(JobName) ->
    gen_server:cast(?MODULE, {execute_now, JobName}).

execute_once(JobName) ->
    gen_server:cast(?MODULE, {execute_once, JobName}).

init([]) ->
    ok = db_worker:recover_stale_jobs(),

    case db_worker:get_active_jobs() of
        {ok, Rows} ->
            State = lists:foldl(fun({ScheduleId, JobName, Payload, CronExpr}, Acc) ->
                %% Calculate next tick ms with cron expr
                NextTickMs = cron_core:next_interval_ms(CronExpr),
                erlang:send_after(NextTickMs, self(), {tick, JobName}),
                maps:put(JobName, {ScheduleId, json:decode(Payload), CronExpr}, Acc)
            end, #{}, Rows),
            {ok, State};
        {error, Reason} ->
            {stop, {db_hydration_failed, Reason}}
    end.

handle_cast({execute_now, JobName}, State) ->
    case maps:find(JobName, State) of
        {ok, {ScheduleId, Payload, _CronExpr}} ->
            ok = db_worker:register_job_run(ScheduleId, Payload),
            {noreply, State};
        error ->
            error_logger:warning_msg("[job_scheduler]: Job ~p not found for execute_now~n", [JobName]),
            {noreply, State}
    end;

handle_cast({active_job, Id}, State) ->
    case db_worker:active_job_by_id(Id) of
        {ok, ScheduleId, JobName, Payload, CronExpr} ->
            NextTickMs = cron_core:next_interval_ms(CronExpr),
            erlang:send_after(NextTickMs, self(), {tick, JobName}),
            {noreply, maps:put(JobName, {ScheduleId, json:decode(Payload), CronExpr}, State)};
        empty ->
            error_logger:warning_msg("[job_scheduler]: Job ~p not found for active job~n", [Id]),
            {noreply, State};
        {error, Reason} ->
            error_logger:error_msg("[job_consumer] Failed on polling: ~p~n", [Reason]),
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call({schedule, JobName, Payload, CronExpr}, _From, State) ->
    {ok, ScheduleId} = db_worker:register_schedule(JobName, Payload, CronExpr),
    ok = db_worker:register_job_run(ScheduleId, Payload),
    error_logger:info_msg("[job_scheduler]: New cron Definition ~p (~p) for ~p", [JobName, ScheduleId, CronExpr]),
    {reply, {ok, ScheduleId}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_info({tick, JobName}, State) ->
    case maps:find(JobName, State) of
        {ok, {ScheduleId, Payload, CronExpr}} ->
            NextTickMs = cron_core:next_interval_ms(CronExpr),
            ok = db_worker:register_job_run(ScheduleId, Payload, <<"queue">>),
            erlang:send_after(NextTickMs, self(), {tick, JobName}),
            {noreply, State};
        error ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

