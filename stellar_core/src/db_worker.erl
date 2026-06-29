-module(db_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([
    start_link/1,
    fetch_and_lock_job/0,
    mark_job_done/2,
    mark_job_dependency/2,
    execute_query/2, 
    insert_returning/2,
    fetch_rows/2,
    register_job_run/2,
    register_job_run/3,
    register_schedule/3,
    register_dependencies/2,
    get_active_jobs/0,
    active_job_by_id/1,
    recover_stale_jobs/0,
    in_queue_job/1,
    job_unlock_dependence/1,
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
register_job_run(ScheduleId, Payload) ->
    register_job_run(ScheduleId, Payload, <<"pending">>).

register_job_run(ScheduleId, Payload, Status) ->
    Query = "INSERT INTO job_runs(schedule_id, payload, status) VALUES ($1, $2, $3)",
    JsonPayload = normalize_payload(Payload),
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {execute_query, Query, [ScheduleId, json:encode(JsonPayload), Status]})
    end).

register_schedule(JobName, Payload, Cron) ->
    Query = "INSERT INTO job_schedules (name, payload_template, cron_expr) VALUES ($1, $2, $3) RETURNING id",
    JsonPayload = normalize_payload(Payload),
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {insert_returning, Query, [JobName, json:encode(JsonPayload), Cron]})
    end).

register_dependencies(JobChildId, JobParentId) ->
    Query = "INSERT INTO job_dependencies (child_schedule_id, parent_schedule_id) VALUES ($1, $2)",
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {execute_query, Query, [JobChildId, JobParentId]})
    end). 

get_active_jobs() ->
    Query = """
        WITH j_runs AS (
            SELECT schedule_id 
            FROM job_runs AS jr
            WHERE jr.status <> 'blocked'
            ORDER BY id
            LIMIT 1
        )
        SELECT 
            id, name, payload_template, cron_expr 
        FROM job_schedules AS js
        INNER JOIN j_runs AS jr ON jr.schedule_id = js.id
        WHERE js.is_active = true
    """,
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {fetch_rows, Query, []})
    end).

recover_stale_jobs() ->
    Query = "UPDATE job_runs SET status = 'pending' WHERE status = 'processing'",
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

mark_job_dependency(JobId, Parents) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {mark_job_dependency, JobId, Parents})
    end).

in_queue_job(ScheduleId) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:cast(Worker, {in_queue_job, ScheduleId})
    end).

job_unlock_dependence(JobId) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:cast(Worker, {job_unlock_dependence, JobId})
    end).

active_job_by_id(JobId) ->
    poolboy:transaction(db_pool, fun(Worker) ->
        gen_server:call(Worker, {active_job_by_id, JobId})
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
        UPDATE job_runs 
        SET status = 'processing' 
        WHERE id = (
            SELECT id FROM job_runs
            WHERE status = 'queue'
            ORDER BY id ASC
            LIMIT 1
            FOR UPDATE SKIP LOCKED
        )
        RETURNING id, payload, schedule_id
    """,

    case epgsql:squery(Conn, Query) of
        {ok, 1, _Cols, [{Id, Payload, ScheduleId}]} -> {reply, {ok, Id, Payload, ScheduleId}, Conn};
        {ok, 0, _Cols, []} -> {reply, empty, Conn};
        Error -> {reply, {error, Error}, Conn}
    end;

handle_call({active_job_by_id, JobId}, _From, Conn) ->
    Query = """
        UPDATE job_schedules
        SET is_active = true
        WHERE id = $1
        RETURNING id, name, payload_template, cron_expr
    """,

    case epgsql:equery(Conn, Query, [JobId]) of
        {ok, 1, _Cols, [{Id, Name, Payload, CronExpr}]} -> {reply, {ok, Id, Name, Payload, CronExpr}, Conn};
        {ok, 0, _Cols, []} -> {reply, empty, Conn};
        Error -> {reply, {error, Error}, Conn}
    end;

handle_call({mark_job_done, JobId, Result}, _From, Conn) ->
    Status = case Result of success -> "completed"; error -> "failed" end,
    Query = "UPDATE job_runs SET status = $1 WHERE id = $2",
    case epgsql:equery(Conn, Query, [Status, JobId]) of
        {ok, _} ->
            {reply, ok, Conn};
        {error, Reason} ->
            {reply, {error, Reason}, Conn}
    end;

handle_call({mark_job_dependency, ScheduleId, Parents}, _From, Conn) ->
    Query = """
        UPDATE job_runs 
        SET status             = 'blocked',
            pending_parents = $1
        WHERE schedule_id = $2
        AND status = 'pending'
    """,
    case epgsql:equery(Conn, Query, [Parents, ScheduleId]) of
        {ok, _} ->
            {reply, ok, Conn};
        {error, Reason} ->
            {reply, {error, Reason}, Conn}
    end.

handle_cast({in_queue_job, ScheduleId}, Conn) ->
    Query = """
        UPDATE job_runs
            SET status = 'queue'
        WHERE schedule_id = $1
        AND status = 'pending'
    """,
    case epgsql:equery(Conn, Query, [ScheduleId]) of
        {ok, _} ->
            {noreply, Conn};
        {error, _Reason} ->
            {noreply, Conn}
    end;

handle_cast({job_unlock_dependence, JobId}, Conn) ->
    Query = """
        WITH updated_children AS (
            UPDATE job_runs AS jr
            SET pending_parents = array_remove(pending_parents, $1)
            FROM job_schedules AS js
            WHERE jr.schedule_id = js.id
            AND jr.status = 'blocked'
            AND js.is_active = true
            AND $1 = ANY(pending_parents)
            RETURNING jr.id, pending_parents
        )
        UPDATE job_runs
        SET status = 'queue'
        WHERE id IN (SELECT id FROM updated_children WHERE pending_parents = '{}')
    """,
    case epgsql:equery(Conn, Query, [JobId]) of
        {ok, _} ->
            {noreply, Conn};
        {error, _Reason} ->
            {noreply, Conn}
    end;

handle_cast(_Msg, Conn) -> {noreply, Conn}.

handle_info(_Info, Conn) -> {noreply, Conn}.

%% setup_table(Conn) ->
%%    epgsql:squery(Conn,
%%         """
%%             CREATE TABLE IF NOT EXISTS job_schedules (
%%                 id UUID PRIMARY KEY DEFAULT uuidv7(),
%%                 name VARCHAR UNIQUE NOT NULL,
%%                 cron_expr VARCHAR,
%%                 payload_template JSONB NOT NULL,
%%                 is_active BOOLEAN DEFAULT false
%%             )
%%         """
%%     ),
%%     epgsql:squery(Conn,
%%         """
%%             CREATE TABLE IF NOT EXISTS job_runs (
%%                 id UUID PRIMARY KEY DEFAULT uuidv7(),
%%                 schedule_id UUID REFERENCES job_schedules (id) ON DELETE SET NULL,
%%                 payload JSONB,
%%                 pending_parents UUID[] DEFAULT '{}',
%%                 status VARCHAR DEFAULT 'pending'
%%             );
%%             CREATE INDEX idx_job_runs_pending_parents 
%%             ON job_runs USING GIN (pending_parents) 
%%             WHERE status = 'pending';
%%         """
%%     ),
%%     epgsql:squery(Conn,
%%         """
%%          CREATE TABLE IF NOT EXISTS job_dependencies (
%%            parent_schedule_id UUID REFERENCES job_schedules(id) ON DELETE CASCADE,
%%            child_schedule_id UUID REFERENCES job_schedules(id) ON DELETE CASCADE,
%%            PRIMARY KEY (parent_schedule_id, child_schedule_id)
%%            );
%%             CREATE INDEX idx_child_job ON job_dependencies(child_job_id);
%%         """
%%     ).
%% 
normalize_payload(Payload) ->
    case Payload of
        {CmdType, CmdString} when is_list(CmdString) ->
            #{CmdType => list_to_binary(CmdString)};
        AlreadyMap when is_map(AlreadyMap) ->
            AlreadyMap
    end.
