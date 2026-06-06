-module(job_scheduler).
-behaviour(gen_server).

-export([start_link/0, add_cron_job/3, execute_now/1, execute_once/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_cron_job(JobName, Payload, CronExpr) ->
    gen_server:cast(?MODULE, {schedule, JobName, Payload, CronExpr}).

execute_now(JobName) ->
    gen_server:cast(?MODULE, {execute_now, JobName}).

execute_once(JobName) ->
    gen_server:cast(?MODULE, {execute_once, JobName}).

init([]) ->
    ok = db_worker:recover_stale_jobs(),

    case db_worker:get_active_crons() of
        {ok, Rows} ->
            State = lists:foldl(fun({CronId, JobName, Payload, Cron}, Acc) ->
                %% Parse cron to int temp
                %% add support for cron expressions
                CronNumber = binary_to_integer(Cron),
                erlang:send_after(CronNumber, self(), {tick, JobName}),
                maps:put(JobName, {CronId, json:decode(Payload), CronNumber}, Acc)
            end, #{}, Rows),
            {ok, State};
        {error, Reason} ->
            {stop, {db_hydration_failed, Reason}}
    end.

handle_cast({execute_now, JobName}, State) ->
    case maps:find(JobName, State) of
        {ok, {CronDefId, Payload, _CronExpr}} ->
            ok = db_worker:register_job(CronDefId, Payload),
            {noreply, State};
        error ->
            error_logger:warning_msg("[job_scheduler]: Job ~p not found for execute_now~n", [JobName]),
            {noreply, State}
    end;

handle_cast({schedule, JobName, Payload, CronExpr}, State) ->
    {ok, CronDefId} = db_worker:register_cron(JobName, Payload, CronExpr),
    error_logger:info_msg("[job_scheduler]: New cron Definition ~p (~p) for ~p ms~n", [JobName, CronDefId, CronExpr]),
    erlang:send_after(CronExpr, self(), {tick, JobName}),
    {noreply, maps:put(JobName, {CronDefId, Payload, CronExpr}, State)}.

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_info({tick, JobId}, State) ->
    case maps:find(JobId, State) of
        {ok, {CronDefId, Payload, CronExpr}} ->
            ok = db_worker:register_job(CronDefId, Payload),
            erlang:send_after(CronExpr, self(), {tick, JobId}),
            {noreply, State};
        error ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

