-module(job_fsm_sup).
-behaviour(supervisor).

-export([start_link/0, start_job/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_job(proplists:proplist()) -> {ok, pid()} | {ok, pid(), term()} | {error, term()}.
start_job(Opts) ->
    supervisor:start_child(?MODULE, [Opts]).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 5, %% max 5 retry
        period => 10    %%...in 10 seconds
    },
    ChildSpec = #{
        id => job_fsm,
        start => {job_fsm, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [job_fsm]
    },
    {ok, {SupFlags, [ChildSpec]}}.

