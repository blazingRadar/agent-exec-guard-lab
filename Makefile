CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2
ANALYZE_FLAGS ?= -Wall -Wextra -fanalyzer -O2

SRC := src/usernotify_exec_guard.c
BIN := bin/usernotify_exec_guard

.PHONY: build analyze test test-syntax test-policy replay-identity replay-audit demo policy-workflow clean

build: $(BIN)

$(BIN): $(SRC) | bin
	$(CC) $(CFLAGS) -o $@ $<

bin:
	mkdir -p bin

analyze:
	$(CC) $(ANALYZE_FLAGS) -o /tmp/usernotify_exec_guard_analyzer $(SRC)
	rm -f /tmp/usernotify_exec_guard_analyzer

test: test-syntax test-policy

test-syntax:
	bash -n scripts/demo/run_openhands_guard_demo.sh
	bash -n scripts/demo/observe_generate_review_enforce.sh
	bash -n scripts/replay_sprint2_identity.sh
	bash -n scripts/replay_sprint4_audit_integrity.sh
	python3 -m py_compile scripts/policy/compile_policy.py scripts/policy/generate_policy_from_audit.py
	rm -rf scripts/policy/__pycache__

test-policy:
	scripts/policy/compile_policy.py policy/examples/openhands_action_server.yaml /tmp/openhands_action_server.allow.json
	printf '%s\n' 'policy_id: local_existing_paths' 'allowed_executables:' '  - /bin/cat' > /tmp/agent_exec_guard_existing_paths.yaml
	scripts/policy/compile_policy.py /tmp/agent_exec_guard_existing_paths.yaml /tmp/agent_exec_guard_existing_paths.json --check-exists
	rm -f /tmp/openhands_action_server.allow.json
	rm -f /tmp/agent_exec_guard_existing_paths.yaml /tmp/agent_exec_guard_existing_paths.json

replay-identity: build
	./scripts/replay_sprint2_identity.sh

replay-audit: build
	./scripts/replay_sprint4_audit_integrity.sh

demo:
	./scripts/demo/run_openhands_guard_demo.sh

policy-workflow:
	./scripts/demo/observe_generate_review_enforce.sh

clean:
	rm -f /tmp/usernotify_exec_guard_analyzer /tmp/openhands_action_server.allow.json
	rm -f /tmp/agent_exec_guard_existing_paths.yaml /tmp/agent_exec_guard_existing_paths.json
	rm -rf scripts/policy/__pycache__
