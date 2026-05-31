-module(worker_pool_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 5, %% max 5 retry
        period => 10    %%...in 10 seconds
    },
    ChildSpec = #{
        id => worker,
        start => {job_worker, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [job_worker]
    },
    {ok, {SupFlags, [ChildSpec]}}.

