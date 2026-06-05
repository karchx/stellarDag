-module(job_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

init([]) ->
    {ok, #{}}.

handle_cast({execute, JobName, PayloadMap, FsmPid}, State) ->
    error_logger:info_msg("[job_worker] executing job ~p~n", [JobName]),
    Port = dispatch_execution(PayloadMap),
    {noreply, State#{port => Port, job_id => JobName, fsm_pid => FsmPid}};

handle_cast(Msg, State) ->
    error_logger:warning_msg("[job_worker] Unhandled cast: ~p~n", [Msg]),
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, {error, not_supported}, State}.

handle_info({Port, {data, Data}}, State = #{port := Port, job_id := JobId}) ->
    error_logger:info_msg("[job_worker] [Job: ~p] Output: ~s", [JobId, Data]),
    {noreply, State};

handle_info({Port, {exit_status, Status}}, State = #{port := Port, job_id := JobId, fsm_pid := FsmPid}) ->
    Result = case Status of
        0 -> success;
        _ ->
            error_logger:error_msg("[job_worker] [Job: ~p] Failed status ~p~n", [JobId, Status]),
            error
    end,
    job_fsm:job_finished(FsmPid, Result),
    worker_pool:release_worker(self()),
    {noreply, maps:without([port, job_id, fsm_pid], State)};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% dispatch execution types
%% bash
%% docker
%% k8s
%% etc.
dispatch_execution(#{<<"bash">> := CommandBin}) ->
    CommandStr = binary_to_list(CommandBin),
    erlang:open_port({spawn, "bash -c \"" ++ CommandStr ++ "\""}, [stream, exit_status]).

