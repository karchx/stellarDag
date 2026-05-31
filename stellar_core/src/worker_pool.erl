-module(worker_pool).
-behaviour(gen_server).

%% API - called
-export([start_link/1, request_worker/0, release_worker/1, execute/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, handle_continue/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(WORKER_SUP, worker_pool_sup).

-record(state, {
    max_workers :: pos_integer(),
    free_workers = [] :: [pid()],
    pending_fsms = queue:new() :: queue:queue()
}).

%% =========== API ===========
%% Opts: [{max_workers, N}]
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec request_worker() -> {ok, pid()} | {error, pool_exhausted}.
request_worker() ->
    gen_server:call(?SERVER, request_worker).

-spec release_worker(pid()) -> ok.
release_worker(WorkerPid) ->
    gen_server:cast(?SERVER, {release_worker, WorkerPid}).

-spec execute(pid(), term(), pid()) -> ok.
execute(WorkerPid, JobId, FsmPid) ->
    gen_server:cast(WorkerPid, {execute, JobId, FsmPid}).

%% ===== CALLBACKS =====
init(Opts) ->
    MaxWorkers = proplists:get_value(max_workers, Opts, 10),

    {ok, #state{max_workers = MaxWorkers}, {continue, init_workers}}.

handle_continue(init_workers, State = #state{max_workers = MaxWorkers}) ->
    Workers = [spawn_worker() || _ <- lists:seq(1, MaxWorkers)],
    {noreply, State#state{free_workers = Workers}}.

handle_call(request_worker, {FsmPid, _Tag}, State = #state{free_workers = Free, pending_fsms = Q}) ->
   case Free of
       [Worker | Rest] ->
           {reply, {ok, Worker}, State#state{free_workers = Rest}};
       [] ->
           NewQ = queue:in(FsmPid, Q),
           {reply, {error, pool_exhausted}, State#state{pending_fsms = NewQ}}
   end;

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({release_worker, WorkerPid}, State = #state{free_workers = Free, pending_fsms = Q}) ->
    case queue:out(Q) of
        {{value, FsmPid}, NewQ} ->
            job_fsm:assign_worker(FsmPid, WorkerPid),
            {noreply, State#state{pending_fsms = NewQ}};
        {empty, _} ->
            {noreply, State#state{free_workers = [WorkerPid | Free]}}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, DeadPid, _Reason},
           State = #state{free_workers = Free, pending_fsms = Q}) ->
    Free1 = lists:delete(DeadPid, Free),
    NewWorker = spawn_worker(),

    case queue:out(Q) of
        {{value, FsmPid}, NewQ} ->
            job_fsm:assign_worker(FsmPid, NewWorker),
            {noreply, State#state{free_workers = Free1, pending_fsms = NewQ}};
        {empty, _} ->
            {noreply, State#state{free_workers = [NewWorker | Free1]}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ===== INTERNAL =====
spawn_worker() ->
    {ok, Pid} = supervisor:start_child(?WORKER_SUP, []),
    erlang:monitor(process, Pid),
    Pid.

