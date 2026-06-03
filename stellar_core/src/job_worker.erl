-module(job_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

init([]) ->
    {ok, #{}}.

handle_cast({execute, JobId, Payload, FsmPid}, State) ->
    Result = do_work(JobId, Payload),
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

do_work(JobId, {bash, Command}) ->
    error_logger:info_msg("[job_worker] executing job ~p~n", [JobId]),
    Port = erlang:open_port({spawn, "bash -c \"" ++ Command ++ "\""}, [stream, exit_status]),
    wait_for_port(Port, JobId).

wait_for_port(Port, JobId) ->
    receive
        {Port, {data, Data}} ->
            error_logger:info_msg("[job_worker] [Job: ~p] Output: ~s", [JobId, Data]),
            wait_for_port(Port, JobId);
        {Port, {exit_status, 0}} ->
            success;
        {Port, {exit_status, Status}} ->
            error_logger:error_msg("[job_worker] [Job: ~p] Failed status ~p~n", [JobId, Status]),
            flush_port_close(Port),
            error
    end.

flush_port_close(Port) ->
    receive
        {Port, closed} -> ok
    after 0 -> 
        ok
    end.

