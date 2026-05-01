#!/usr/bin/env bash
set -u

ROOT="${AEG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
POLICY_YAML="$ROOT/policy/examples/openhands_action_server.yaml"
MODEL_NAME="${SPRINT9_MODEL:-openai/gpt-5.2}"
ENV_FILE=""
RUN_ID="sprint9-demo-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint9_runs/$RUN_ID"
OPENHANDS_RUN_ROOT=""
pass_count=0
fail_count=0

usage() {
  cat <<'EOF'
Usage: scripts/demo/run_openhands_guard_demo.sh [options]

Options:
  --policy-yaml PATH   YAML policy source to compile before the run.
  --model MODEL        OpenHands/LiteLLM model name. Default: openai/gpt-5.2.
  --env-file PATH      Optional shell env file containing OPENAI_API_KEY.
  -h, --help           Show this help.
EOF
}

cleanup_runtime() {
  local run_root="$OPENHANDS_RUN_ROOT"
  local container_name=""
  if [ -z "$run_root" ] && [ -f "$ROOT/proofs/sprint8_runs/latest_frontier_agent.txt" ]; then
    run_root="$(cat "$ROOT/proofs/sprint8_runs/latest_frontier_agent.txt")"
  fi
  if [ -n "$run_root" ] && [ -f "$run_root/runtime_container_status.txt" ]; then
    container_name="$(awk '{print $1; exit}' "$run_root/runtime_container_status.txt")"
  fi
  if [ -n "$container_name" ]; then
    sg docker -c "docker rm -f '$container_name'" \
      >"$RUN_ROOT/post_run_container_cleanup.stdout" \
      2>"$RUN_ROOT/post_run_container_cleanup.stderr" || true
  fi
}

finish() {
  local rc=$?
  cleanup_runtime
  if [ -n "${SUMMARY:-}" ] && [ -f "$SUMMARY" ]; then
    printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$SUMMARY" >/dev/null
  fi
  exit "$rc"
}

trap finish EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --policy-yaml)
      POLICY_YAML="$2"
      shift 2
      ;;
    --model)
      MODEL_NAME="$2"
      shift 2
      ;;
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$RUN_ROOT/policy" "$RUN_ROOT/compiler_negative" "$RUN_ROOT/openhands_runs"
printf '%s\n' "$RUN_ROOT" >"$ROOT/proofs/sprint9_runs/latest_demo.txt"

SUMMARY="$RUN_ROOT/demo_summary.txt"
COMMAND_LOG="$RUN_ROOT/command_log.txt"
COMPILED_POLICY="$RUN_ROOT/policy/openhands_action_server.allow.json"
COMPILED_POLICY_SANDBOX="/lab/proofs/sprint9_runs/$RUN_ID/policy/openhands_action_server.allow.json"

log_cmd() {
  printf '$ %s\n' "$*" | tee -a "$COMMAND_LOG"
}

record() {
  local status="$1"
  local name="$2"
  local message="$3"
  printf '%s %s %s\n' "$status" "$name" "$message" | tee -a "$SUMMARY"
  if [ "$status" = "PASS" ]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
}

printf 'run_id=%s\n' "$RUN_ID" >"$SUMMARY"
printf 'run_root=%s\n' "$RUN_ROOT" >>"$SUMMARY"
printf 'model=%s\n' "$MODEL_NAME" >>"$SUMMARY"
printf 'policy_yaml=%s\n' "$POLICY_YAML" >>"$SUMMARY"
printf 'compiled_policy=%s\n' "$COMPILED_POLICY" >>"$SUMMARY"

if [ ! -x "$ROOT/scripts/policy/compile_policy.py" ]; then
  record "FAIL" "preflight_compiler" "missing executable compiler at $ROOT/scripts/policy/compile_policy.py"
  exit 2
else
  record "PASS" "preflight_compiler" "policy compiler present"
fi

if [ ! -x "$ROOT/scripts/integration/replay_sprint8_frontier_agent.sh" ]; then
  record "FAIL" "preflight_replay" "missing Sprint 8 replay harness"
  exit 2
else
  record "PASS" "preflight_replay" "Sprint 8 replay harness present"
fi

if [ ! -d "$ROOT/external/OpenHands-1.6.0/.git" ]; then
  record "FAIL" "preflight_openhands_source" "missing pinned OpenHands source at external/OpenHands-1.6.0"
  exit 2
else
  record "PASS" "preflight_openhands_source" "pinned OpenHands source present"
fi

if ! command -v docker >/dev/null 2>&1; then
  record "FAIL" "preflight_docker" "docker command missing"
  exit 2
fi

if ! sg docker -c "docker info >/dev/null 2>&1"; then
  record "FAIL" "preflight_docker" "docker not reachable via sg docker"
  exit 2
else
  record "PASS" "preflight_docker" "docker reachable via sg docker"
fi

if [ -n "$ENV_FILE" ]; then
  if [ ! -f "$ENV_FILE" ]; then
    record "FAIL" "env_file" "missing env file: $ENV_FILE"
    exit 2
  fi
  log_cmd "source $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  record "PASS" "env_file" "loaded env file path without persisting contents"
else
  record "PASS" "env_file" "no env file requested"
fi

cp "$POLICY_YAML" "$RUN_ROOT/policy/source_policy.yaml"
log_cmd "scripts/policy/compile_policy.py $POLICY_YAML $COMPILED_POLICY"
if "$ROOT/scripts/policy/compile_policy.py" "$POLICY_YAML" "$COMPILED_POLICY" \
  >"$RUN_ROOT/policy/compile.stdout" 2>"$RUN_ROOT/policy/compile.stderr"; then
  record "PASS" "policy_compile" "YAML policy compiled to guard JSON"
else
  record "FAIL" "policy_compile" "YAML policy compile failed"
  exit 1
fi

cat >"$RUN_ROOT/compiler_negative/malformed.yaml" <<'EOF'
policy_id: malformed
allowed_executables: [
EOF
cat >"$RUN_ROOT/compiler_negative/missing_allowed.yaml" <<'EOF'
policy_id: missing_allowed
EOF
cat >"$RUN_ROOT/compiler_negative/relative_path.yaml" <<'EOF'
policy_id: relative_path
allowed_executables:
  - usr/bin/cat
EOF
cat >"$RUN_ROOT/compiler_negative/missing_executable.yaml" <<'EOF'
policy_id: missing_executable
allowed_executables:
  - /definitely/not/a/real/executable
EOF

for case_name in malformed missing_allowed relative_path; do
  input="$RUN_ROOT/compiler_negative/${case_name}.yaml"
  output="$RUN_ROOT/compiler_negative/${case_name}.json"
  log_cmd "scripts/policy/compile_policy.py $input $output"
  if "$ROOT/scripts/policy/compile_policy.py" "$input" "$output" \
    >"$RUN_ROOT/compiler_negative/${case_name}.stdout" \
    2>"$RUN_ROOT/compiler_negative/${case_name}.stderr"; then
    record "FAIL" "compiler_rejects_${case_name}" "compiler accepted invalid policy"
  else
    record "PASS" "compiler_rejects_${case_name}" "compiler rejected invalid policy"
  fi
done

log_cmd "scripts/policy/compile_policy.py --check-exists missing_executable.yaml"
if "$ROOT/scripts/policy/compile_policy.py" --check-exists \
  "$RUN_ROOT/compiler_negative/missing_executable.yaml" \
  "$RUN_ROOT/compiler_negative/missing_executable.json" \
  >"$RUN_ROOT/compiler_negative/missing_executable.stdout" \
  2>"$RUN_ROOT/compiler_negative/missing_executable.stderr"; then
  record "FAIL" "compiler_rejects_missing_executable" "compiler accepted missing executable with --check-exists"
else
  record "PASS" "compiler_rejects_missing_executable" "compiler rejected missing executable with --check-exists"
fi

if [ -n "${OPENAI_API_KEY:-}" ]; then
  record "PASS" "openai_api_key_present" "OPENAI_API_KEY present in process environment"
else
  record "FAIL" "openai_api_key_present" "OPENAI_API_KEY missing; external-model demo not launched"
  exit 2
fi

log_cmd "SPRINT8_RUNS_DIR=$RUN_ROOT/openhands_runs SPRINT8_POLICY_JSON_HOST=$COMPILED_POLICY SPRINT8_POLICY_JSON_SANDBOX=$COMPILED_POLICY_SANDBOX scripts/integration/replay_sprint8_frontier_agent.sh"
if SPRINT8_ROOT="$ROOT" \
  SPRINT8_MODEL="$MODEL_NAME" \
  SPRINT8_RUNS_DIR="$RUN_ROOT/openhands_runs" \
  SPRINT8_POLICY_JSON_HOST="$COMPILED_POLICY" \
  SPRINT8_POLICY_JSON_SANDBOX="$COMPILED_POLICY_SANDBOX" \
  "$ROOT/scripts/integration/replay_sprint8_frontier_agent.sh" \
  >"$RUN_ROOT/openhands_replay.stdout" 2>"$RUN_ROOT/openhands_replay.stderr"; then
  record "PASS" "openhands_guard_demo" "OpenHands frontier-model guard demo completed"
else
  record "FAIL" "openhands_guard_demo" "OpenHands frontier-model guard demo failed"
  exit 1
fi

OPENHANDS_RUN_ROOT="$(cat "$ROOT/proofs/sprint8_runs/latest_frontier_agent.txt")"
printf 'openhands_run_root=%s\n' "$OPENHANDS_RUN_ROOT" >>"$SUMMARY"

if [ -f "$OPENHANDS_RUN_ROOT/replay_summary.txt" ] && grep -q '^pass=' "$OPENHANDS_RUN_ROOT/replay_summary.txt"; then
  record "PASS" "openhands_summary_present" "$OPENHANDS_RUN_ROOT/replay_summary.txt"
else
  record "FAIL" "openhands_summary_present" "missing OpenHands replay summary"
fi

sha256sum "$ROOT/src/usernotify_exec_guard.c" \
  "$ROOT/bin/usernotify_exec_guard" \
  "$ROOT/scripts/demo/run_openhands_guard_demo.sh" \
  "$ROOT/scripts/policy/compile_policy.py" \
  "$POLICY_YAML" \
  "$COMPILED_POLICY" >"$RUN_ROOT/sha256s.txt"

if grep -RqsE 'sk-proj-|sk-[A-Za-z0-9_-]{20,}' "$RUN_ROOT"; then
  record "FAIL" "secret_scan" "potential API key pattern found in Sprint 9 run artifacts"
  exit 1
else
  record "PASS" "secret_scan" "no API key pattern found in Sprint 9 run artifacts"
fi

if grep -q '^FAIL ' "$SUMMARY"; then
  exit 1
fi

exit 0
