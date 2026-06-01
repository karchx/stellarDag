-module(job_scheduler).
-behaviour(gen_server).

-export([start_link/0, add_cron_job/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_cron_job(JobId, Payload, IntervalMs) ->
    gen_server:cast(?MODULE, {schedule, JobId, Payload, IntervalMs}).

init([]) ->
    {ok, #{}}.

handle_cast({schedule, JobId, Payload, IntervalMs}, State) ->
    error_logger:info_msg("[job_scheduler]: Created cron ~p for ~p ms~n", [JobId, IntervalMs]),
    erlang:send_after(IntervalMs, self(), {tick, JobId}),
    {noreply, maps:put(JobId, {Payload, IntervalMs}, State)};

handle_cast({job_done, JobId, Result}, State) ->
    error_logger:info_msg("[job_scheduler] Job ~p finished with result ~p~n", [JobId, Result]),
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_info({tick, JobId}, State) ->
    case maps:find(JobId, State) of
        {ok, {Payload, IntervalMs}} ->
            {ok, _Pid} = job_fsm:start_link([
                {job_id, JobId},
                {payload, Payload},
                {orchestrator_pid, self()}
            ]),
            erlang:send_after(IntervalMs, self(), {tick, JobId}),
            {noreply, State};
        error ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

