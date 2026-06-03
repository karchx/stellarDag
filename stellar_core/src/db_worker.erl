-module(db_worker).
-behaviour(gen_server).

-export([start_link/0, fetch_and_lock_job/0, mark_job_done/2, setup_table/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).


start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Config = #{
        host => "localhost",
        username => "postgres",
        password => "postgres",
        database => "stellar_core",
        timeout => 4000
    },
    {ok, Conn} = epgsql:connect(Config),
    setup_table(Conn),
    {ok, Conn}.


%% ====== API =====
-spec fetch_and_lock_job() -> {ok, pid()} | {error, pool_exhausted}.
fetch_and_lock_job() ->
    gen_server:call(?MODULE, fetch_and_lock_job).

-spec mark_job_done(pid(), term()) -> {ok, pid()} | {error, pool_exhausted}.
mark_job_done(JobId, Result) ->
    gen_server:call(?MODULE, {mark_job_done, JobId, Result}).

handle_call(fetch_and_lock_job, _From, Conn) ->
    Query = """
        UPDATE jobs_queue 
        SET status = 'processing' 
        WHERE id = (
            SELECT id FROM jobs_queue
            WHERE status = 'pending'
            LIMIT 1
            FROM UPDATE SKIP LOCKED
        )
        RETURNING id, payload
    """,

    case epgsql:squery(Conn, Query) of
        {ok, 1, _Cols, [{Id, Payload}]} -> {reply, {ok, Id, Payload}, Conn};
        {ok, 0, _Cols, []} -> {reply, empty, Conn};
        Error -> {reply, {error, Error}, Conn}
    end;

handle_call({mark_job_done, JobId, Result}, _From, Conn) ->
    Status = case Result of success -> "completed"; error -> "failed" end,
    Query = io_lib:format("UPDATE jobs_queue SET status = '~s' WHERE id = '~s'", [Status, JobId]),
    {ok, _} = epgsql:squery(Conn, lists:flatten(Query)),
    {reply, ok, Conn}.

handle_cast(_Msg, Conn) -> {noreply, Conn}.
handle_info(_Info, Conn) -> {noreply, Conn}.

setup_table(Conn) ->
    epgsql:squery(Conn,
        "CREATE TABLE IF NOT EXISTS jobs_queue (id UUID PRIMARY KEY DEFAULT uuidv7(), payload JSONB, status VARCHAR DEFAULT 'pending')").
