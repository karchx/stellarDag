REBAR=`which rebar3 || echo ./rebar3`

all: deps compile

deps:
	@( $(REBAR) get-deps)

compile:
	@( $(REBAR) compile)

clean:
	@( $(REBAR) clean)

test:
	erlc -DTEST src/workflow_fsm.erl
	erl -noshell -eval "eunit:test(workflow_fsm, [verbose])" -s init stop

.PHONY: all, deps, compile
