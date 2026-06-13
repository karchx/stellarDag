-module(db_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([
    start_link/1,
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

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

init(_Args) ->
    Config = #{
        host => "postgres-postgresql.platform.svc.cluster.local",
        username => "platform",
        password => "changeme123",
        database => "stellar_core",
        timeout => 4000
    },
    {ok, Conn} = epgsql:connect(Config),
    %% setup_table(Conn),
    {ok, Conn}.

%% ====== API =====

register_job(CronDefId, Payload) ->
    Query = "INSERT INTO jobs_queue(cron_definition_id, payload, status) VALUES ($1, $2, 'pending')",
    JsonPayload = normalize_payload(Payload),
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {execute_query, Query, [CronDefId, json:encode(JsonPayload)]})
    end).

register_cron(JobName, Payload, Cron) ->
    Query = "INSERT INTO cron_definitions (name, payload_template, cron) VALUES ($1, $2, $3) RETURNING id",
    JsonPayload = normalize_payload(Payload),
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {insert_returning, Query, [JobName, json:encode(JsonPayload), Cron]})
    end).

get_active_crons() ->
    Query = "SELECT id, name, payload_template, cron FROM cron_definitions WHERE is_active = true",
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {fetch_rows, Query, []})
    end).

recover_stale_jobs() ->
    Query = "UPDATE jobs_queue SET status = 'pending' WHERE status = 'processing'",
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {execute_query, Query, []})
    end).

fetch_and_lock_job() ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, fetch_and_lock_job)
    end).

mark_job_done(JobId, Result) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {mark_job_done, JobId, Result})
    end).

execute_query(Query, Params) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {execute_query, Query, Params})
    end).

insert_returning(Query, Params) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {insert_returning, Query, Params})
    end).

fetch_rows(Query, Params) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {fetch_rows, Query, Params})
    end).

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
            #{CmdType => list_to_binary(CmdString)};
        AlreadyMap when is_map(AlreadyMap) ->
            AlreadyMap
    end.
