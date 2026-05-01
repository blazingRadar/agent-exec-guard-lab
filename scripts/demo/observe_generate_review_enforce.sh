#!/usr/bin/env bash
set -u

ROOT="${AEG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RUN_ID="sprint10-policy-workflow-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint10_runs/$RUN_ID"
MODEL_NAME="${SPRINT10_MODEL:-openai/gpt-5.2}"
ENV_FILE=""
OBSERVE_RUN_ROOT=""
pass_count=0
fail_count=0

usage() {
  cat <<'EOF'
Usage: scripts/demo/observe_generate_review_enforce.sh [options]

Options:
  --observe-run-root PATH  Existing Sprint 9/OpenHands run root to generate policy from.
  --model MODEL            Model for enforce rerun. Default: openai/gpt-5.2.
  --env-file PATH          Optional shell env file containing OPENAI_API_KEY.
  -h, --help               Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --observe-run-root)
      OBSERVE_RUN_ROOT="$2"
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

mkdir -p "$RUN_ROOT"
printf '%s\n' "$RUN_ROOT" >"$ROOT/proofs/sprint10_runs/latest_policy_workflow.txt"
SUMMARY="$RUN_ROOT/workflow_summary.txt"
COMMAND_LOG="$RUN_ROOT/command_log.txt"

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

log_cmd() {
  printf '$ %s\n' "$*" | tee -a "$COMMAND_LOG"
}

finish() {
  if [ -n "${SUMMARY:-}" ] && [ -f "$SUMMARY" ]; then
    printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$SUMMARY" >/dev/null
  fi
}
trap finish EXIT

printf 'run_id=%s\n' "$RUN_ID" >"$SUMMARY"
printf 'run_root=%s\n' "$RUN_ROOT" >>"$SUMMARY"
printf 'model=%s\n' "$MODEL_NAME" >>"$SUMMARY"

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

if [ -z "$OBSERVE_RUN_ROOT" ]; then
  if [ -f "$ROOT/proofs/sprint9_runs/latest_demo.txt" ]; then
    sprint9_root="$(cat "$ROOT/proofs/sprint9_runs/latest_demo.txt")"
    OBSERVE_RUN_ROOT="$(find "$sprint9_root/openhands_runs" -maxdepth 1 -mindepth 1 -type d | sort | tail -1)"
  fi
fi

if [ -z "$OBSERVE_RUN_ROOT" ] || [ ! -d "$OBSERVE_RUN_ROOT" ]; then
  record "FAIL" "observe_run_root" "missing observed OpenHands run root"
  exit 2
fi

OBSERVE_LOG="$OBSERVE_RUN_ROOT/runtime_container_logs.combined"
if [ ! -f "$OBSERVE_LOG" ]; then
  record "FAIL" "observe_log" "missing guard log: $OBSERVE_LOG"
  exit 2
fi

printf 'observe_run_root=%s\n' "$OBSERVE_RUN_ROOT" >>"$SUMMARY"
printf 'observe_log=%s\n' "$OBSERVE_LOG" >>"$SUMMARY"
record "PASS" "observe_log" "$OBSERVE_LOG"

GENERATED_YAML="$RUN_ROOT/generated/openhands_observed.allow.yaml"
BLOCKED_JSON="$RUN_ROOT/generated/blocked_records.json"
GENERATED_JSON="$RUN_ROOT/generated/openhands_observed.allow.json"

log_cmd "scripts/policy/generate_policy_from_audit.py $OBSERVE_LOG $GENERATED_YAML"
if "$ROOT/scripts/policy/generate_policy_from_audit.py" \
  "$OBSERVE_LOG" "$GENERATED_YAML" \
  --policy-id "sprint10_observed_openhands_policy_v1" \
  --include-blocked-summary "$BLOCKED_JSON" \
  >"$RUN_ROOT/generate_policy.stdout" 2>"$RUN_ROOT/generate_policy.stderr"; then
  record "PASS" "generate_policy" "generated reviewable YAML from observed guard log"
else
  record "FAIL" "generate_policy" "policy generation failed"
  exit 1
fi

log_cmd "scripts/policy/compile_policy.py $GENERATED_YAML $GENERATED_JSON"
if "$ROOT/scripts/policy/compile_policy.py" "$GENERATED_YAML" "$GENERATED_JSON" \
  >"$RUN_ROOT/compile_generated.stdout" 2>"$RUN_ROOT/compile_generated.stderr"; then
  record "PASS" "compile_generated_policy" "generated YAML compiled to guard JSON"
else
  record "FAIL" "compile_generated_policy" "generated YAML compile failed"
  exit 1
fi

if python3 - "$GENERATED_YAML" "$BLOCKED_JSON" <<'PY' >"$RUN_ROOT/generated_policy_assertions.stdout" 2>"$RUN_ROOT/generated_policy_assertions.stderr"
import json
import sys
import yaml
policy = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
blocked = json.load(open(sys.argv[2], "r", encoding="utf-8"))
allowed = set(policy.get("allowed_executables", []))
assert "/usr/bin/cat" in allowed
assert "/usr/bin/rm" not in allowed
assert any(item.get("raw_exe") == "./python3" for item in blocked.get("blocked", []))
print(json.dumps({
    "allowed_count": len(allowed),
    "blocked_count": blocked.get("blocked_count"),
    "cat_allowed": "/usr/bin/cat" in allowed,
    "rm_allowed": "/usr/bin/rm" in allowed,
    "copied_rm_block_observed": any(
        item.get("raw_exe") == "./python3" for item in blocked.get("blocked", [])
    ),
}, indent=2))
PY
then
  record "PASS" "generated_policy_assertions" "generated policy allows cat, excludes observed blocked rm"
else
  record "FAIL" "generated_policy_assertions" "generated policy assertions failed"
  exit 1
fi

log_cmd "scripts/demo/run_openhands_guard_demo.sh --policy-yaml $GENERATED_YAML"
if "$ROOT/scripts/demo/run_openhands_guard_demo.sh" \
  --policy-yaml "$GENERATED_YAML" \
  --model "$MODEL_NAME" \
  >"$RUN_ROOT/enforce_demo.stdout" 2>"$RUN_ROOT/enforce_demo.stderr"; then
  record "PASS" "enforce_generated_policy" "guided demo passed under generated policy"
else
  record "FAIL" "enforce_generated_policy" "guided demo failed under generated policy"
  exit 1
fi

ENFORCE_RUN_ROOT="$(cat "$ROOT/proofs/sprint9_runs/latest_demo.txt")"
printf 'enforce_run_root=%s\n' "$ENFORCE_RUN_ROOT" >>"$SUMMARY"
if grep -q 'pass=14 fail=0' "$ENFORCE_RUN_ROOT/demo_summary.txt"; then
  record "PASS" "enforce_summary" "$ENFORCE_RUN_ROOT/demo_summary.txt"
else
  record "FAIL" "enforce_summary" "generated-policy enforce summary did not pass"
  exit 1
fi

sha256sum "$ROOT/guard/usernotify_exec_guard.c" \
  "$ROOT/bin/usernotify_exec_guard" \
  "$ROOT/scripts/policy/generate_policy_from_audit.py" \
  "$ROOT/scripts/demo/observe_generate_review_enforce.sh" \
  "$GENERATED_YAML" \
  "$GENERATED_JSON" >"$RUN_ROOT/sha256s.txt"

if grep -RqsE 'sk-proj-|sk-[A-Za-z0-9_-]{20,}' "$RUN_ROOT"; then
  record "FAIL" "secret_scan" "potential API key pattern found in Sprint 10 artifacts"
  exit 1
else
  record "PASS" "secret_scan" "no API key pattern found in Sprint 10 artifacts"
fi

if grep -q '^FAIL ' "$SUMMARY"; then
  exit 1
fi

exit 0
