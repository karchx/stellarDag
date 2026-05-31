-module(job_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

init([]) ->
    {ok, #{}}.

handle_cast({execute, JobId, FsmPid}, State) ->
    Result = do_work(JobId),
    job_fsm:job_finished(FsmPid, Result),
    worker_pool:release_worker(self()),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, {error, not_supported}, State}.

handle_call(_Req, _From, State) ->
    {reply, {error, not_supported}, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

do_work(JobId) ->
    error_logger:info_msg("[job_worker] executing job ~p~n", [JobId]),
    timer:sleep(rand:uniform(500)),
    success.

