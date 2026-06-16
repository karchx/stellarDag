-module(job_scheduler).
-behaviour(gen_server).

-export([start_link/0, add_cron_job/3, execute_now/1, execute_once/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_cron_job(JobName, Payload, CronExpr) ->
    gen_server:call(?MODULE, {schedule, JobName, Payload, CronExpr}).

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

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call({schedule, JobName, Payload, CronExpr}, _From, State) ->
    NextTickMs = cron_core:next_interval_ms(CronExpr),
    {ok, ScheduleId} = db_worker:register_schedule(JobName, Payload, CronExpr),
    error_logger:info_msg("[job_scheduler]: New cron Definition ~p (~p) for ~p", [JobName, ScheduleId, CronExpr]),
    erlang:send_after(NextTickMs, self(), {tick, JobName}),

    {reply, {ok, ScheduleId}, maps:put(JobName, {ScheduleId, Payload, CronExpr}, State)};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_info({tick, JobId}, State) ->
    case maps:find(JobId, State) of
        {ok, {ScheduleId, Payload, CronExpr}} ->
            NextTickMs = cron_core:next_interval_ms(CronExpr),
            ok = db_worker:register_job_run(ScheduleId, Payload),
            erlang:send_after(NextTickMs, self(), {tick, JobId}),
            {noreply, State};
        error ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

