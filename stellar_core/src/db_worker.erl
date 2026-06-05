-module(db_worker).
-behaviour(gen_server).

-export([
    start_link/0,
    fetch_and_lock_job/0,
    mark_job_done/2,
    execute_query/2, 
    insert_returning/2,
    fetch_rows/2,
    setup_table/1,
    register_job/2,
    register_cron/3,
    get_active_crons/0,
    recover_stale_jobs/0,
    normalize_payload/1
]).
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

register_job(CronDefId, Payload) ->
    Query = "INSERT INTO jobs_queue(cron_definition_id, payload, status) VALUES ($1, $2, 'pending')",
    JsonPayload = normalize_payload(Payload),
    gen_server:call(?MODULE, {execute_query, Query, [CronDefId, json:encode(JsonPayload)]}).

register_cron(JobName, Payload, Cron) ->
    Query = "INSERT INTO cron_definitions (name, payload_template, cron) VALUES ($1, $2, $3) RETURNING id",
    JsonPayload = normalize_payload(Payload),
    gen_server:call(?MODULE, {insert_returning, Query, [JobName, json:encode(JsonPayload), Cron]}).

get_active_crons() ->
    Query = "SELECT id, name, payload_template, cron FROM cron_definitions WHERE is_active = true",
    gen_server:call(?MODULE, {fetch_rows, Query, []}).

recover_stale_jobs() ->
    Query = "UPDATE jobs_queue SET status = 'pending' WHERE status = 'processing'",
    gen_server:call(?MODULE, {execute_query, Query, []}).

-spec fetch_and_lock_job() -> {ok, pid()} | {error, pool_exhausted}.
fetch_and_lock_job() ->
    gen_server:call(?MODULE, fetch_and_lock_job).

-spec mark_job_done(pid(), term()) -> {ok, pid()} | {error, pool_exhausted}.
mark_job_done(JobId, Result) ->
    gen_server:call(?MODULE, {mark_job_done, JobId, Result}).

-spec execute_query(string(), term()) -> {ok, pid()} | {error, pool_exhausted}.
execute_query(Query, Params) ->
    gen_server:call(?MODULE, {execute_query, Query, Params}).

-spec insert_returning(string(), term()) -> {ok, pid()} | {error, pool_exhausted}.
insert_returning(Query, Params) ->
    gen_server:call(?MODULE, {insert_returning, Query, Params}).

-spec fetch_rows(string(), term()) -> {ok, pid()} | {error, pool_exhausted}.
fetch_rows(Query, Params) ->
    gen_server:call(?MODULE, {fetch_rows, Query, Params}).

handle_call({execute_query, Query, Params}, _From, Conn) ->
    {ok, _} = epgsql:equery(Conn, Query, Params),
    {reply, ok, Conn};

handle_call({insert_returning, Query, Params}, _From, Conn) ->
    case epgsql:equery(Conn, Query, Params) of
        {ok, _Count, _Columns, [{Id}]} -> {reply, {ok, Id}, Conn};
        Error -> {reply, Error, Conn}
    end;

handle_call({fetch_rows, Query, Params}, _From, Conn) ->
    case epgsql:equery(Conn, Query, Params) of
         {ok, _Columns, Rows} -> {reply, {ok, Rows}, Conn};
         Error -> {reply, Error, Conn}
    end;

handle_call(fetch_and_lock_job, _From, Conn) ->
    Query = """
        UPDATE jobs_queue 
        SET status = 'processing' 
        WHERE id = (
            SELECT id FROM jobs_queue
            WHERE status = 'pending'
            LIMIT 1
            FOR UPDATE SKIP LOCKED
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
    Query = "UPDATE jobs_queue SET status = $1 WHERE id = $2",
    {ok, _} = epgsql:equery(Conn, Query, [Status, JobId]),
    {reply, ok, Conn}.

handle_cast(_Msg, Conn) -> {noreply, Conn}.
handle_info(_Info, Conn) -> {noreply, Conn}.

setup_table(Conn) ->
   epgsql:squery(Conn,
        """
            CREATE TABLE IF NOT EXISTS cron_definitions (
                id UUID PRIMARY KEY DEFAULT uuidv7(),
                name VARCHAR UNIQUE NOT NULL,
                cron VARCHAR,
                payload_template JSONB NOT NULL,
                is_active BOOLEAN DEFAULT true
            )
        """
    ),
    epgsql:squery(Conn,
        """
            CREATE TABLE IF NOT EXISTS jobs_queue (
                id UUID PRIMARY KEY DEFAULT uuidv7(),
                cron_definition_id UUID REFERENCES cron_definitions (id) ON DELETE SET NULL,
                payload JSONB,
                status VARCHAR DEFAULT 'pending'
            )
        """
    ).

normalize_payload(Payload) ->
    case Payload of
        {CmdType, CmdString} when is_list(CmdString) ->
            #{atom_to_binary(CmdType, utf8) => list_to_binary(CmdString)};
        AlreadyMap when is_map(AlreadyMap) ->
            AlreadyMap
    end.
