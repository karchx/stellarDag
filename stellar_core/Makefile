REBAR=`which rebar3 || echo ./rebar3`

all: deps compile

deps:
	@( $(REBAR) get-deps)

compile:
	@( $(REBAR) compile)

clean:
	@( $(REBAR) clean)

test:
	erlc -DTEST src/job_fsm.erl
	erl -noshell -eval "eunit:test(job_fsm, [verbose])" -s init stop

.PHONY: all, deps, compile
