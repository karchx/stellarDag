-module(stellar_core_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ets:new(job_states, [named_table, public, set,
                         {write_concurrency, true},
                         {read_concurrency, true}]),
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 5,
        period => 10
    },
    ChildSpecs = [
        #{id => pg, 
          start => {pg, start_link, []}, 
          restart => permanent, 
          type => worker
        },
        #{id => db_worker,
          start => {db_worker, start_link, []},
          type => worker},
        #{id => worker_pool_sup,
          start => {worker_pool_sup, start_link, []},
          type => supervisor},
        #{id => worker_pool,
          start => {worker_pool, start_link, [[{max_workers, 3}]]},
          type => worker},
        #{id => job_scheduler,
          start => {job_scheduler, start_link, []},
          type => worker}
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
