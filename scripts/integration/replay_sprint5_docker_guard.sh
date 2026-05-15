#!/usr/bin/env bash
set -u

ROOT="${AEG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
IMAGE="python:3.12-slim"
RUN_ID="sprint5-docker-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint5_runs/$RUN_ID"
META_CONTAINER="aeg-${RUN_ID}"
POLICY_IN_CONTAINER="/lab/policy/integration/docker_python_slim.allow.json"
GUARD_IN_CONTAINER="/lab/bin/usernotify_exec_guard"

mkdir -p "$RUN_ROOT"

pass_count=0
fail_count=0

record() {
  local status="$1"
  local name="$2"
  local message="$3"
  printf '%s %s %s\n' "$status" "$name" "$message" | tee -a "$RUN_ROOT/replay_summary.txt"
  if [ "$status" = "PASS" ]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
}

json_valid() {
  local stderr_file="$1"
  python3 - "$stderr_file" <<'PY'
import json
import sys

count = 0
for line in open(sys.argv[1], "r", encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith("{"):
        continue
    json.loads(line)
    count += 1
if count == 0:
    raise SystemExit("no json audit lines found")
PY
}

json_query() {
  local stderr_file="$1"
  local expr="$2"
  python3 - "$stderr_file" "$expr" <<'PY'
import json
import sys

path, expr = sys.argv[1:3]
for line in open(path, "r", encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith("{"):
        continue
    obj = json.loads(line)
    if eval(expr, {}, {"obj": obj}):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

docker_run() {
  sg docker -c "docker run --rm -v '$ROOT:/lab:rw' -w /lab '$IMAGE' $*"
}

record_docker_metadata() {
  local meta_dir="$RUN_ROOT/docker_metadata"
  mkdir -p "$meta_dir"

  sg docker -c "docker rm -f '$META_CONTAINER' >/dev/null 2>&1 || true"
  sg docker -c "docker create --name '$META_CONTAINER' -v '$ROOT:/lab:rw' -w /lab '$IMAGE' /bin/sh -c 'grep \"^Seccomp:\" /proc/self/status; grep \"^NoNewPrivs:\" /proc/self/status'" \
    >"$meta_dir/docker_create.stdout" 2>"$meta_dir/docker_create.stderr"
  local create_rc=$?
  printf '%s\n' "$create_rc" >"$meta_dir/docker_create.exit_code"
  if [ "$create_rc" -ne 0 ]; then
    record "FAIL" "docker_metadata_create" "docker create failed"
    return
  fi

  sg docker -c "docker inspect '$META_CONTAINER'" >"$meta_dir/docker_inspect.json" 2>"$meta_dir/docker_inspect.stderr"
  local inspect_rc=$?
  printf '%s\n' "$inspect_rc" >"$meta_dir/docker_inspect.exit_code"
  if [ "$inspect_rc" -ne 0 ]; then
    record "FAIL" "docker_metadata_inspect" "docker inspect failed"
  else
    record "PASS" "docker_metadata_inspect" "HostConfig retained"
  fi

  python3 - "$meta_dir/docker_inspect.json" >"$meta_dir/hostconfig_securityopt.txt" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
security_opt = data[0].get("HostConfig", {}).get("SecurityOpt")
print(repr(security_opt))
PY
  if grep -qx 'None' "$meta_dir/hostconfig_securityopt.txt"; then
    record "PASS" "docker_securityopt_default" "HostConfig.SecurityOpt=None"
  else
    record "FAIL" "docker_securityopt_default" "HostConfig.SecurityOpt not default"
  fi

  sg docker -c "docker start -a '$META_CONTAINER'" >"$meta_dir/proc_status.stdout" 2>"$meta_dir/proc_status.stderr"
  local start_rc=$?
  printf '%s\n' "$start_rc" >"$meta_dir/proc_status.exit_code"
  sg docker -c "docker rm -f '$META_CONTAINER' >/dev/null 2>&1 || true"
  if [ "$start_rc" -ne 0 ]; then
    record "FAIL" "docker_proc_status" "container status probe failed"
    return
  fi
  if grep -q '^Seccomp:[[:space:]]*2$' "$meta_dir/proc_status.stdout"; then
    record "PASS" "docker_proc_status_seccomp" "container reports Seccomp:2"
  else
    record "FAIL" "docker_proc_status_seccomp" "missing Seccomp:2"
  fi
}

run_case() {
  local name="$1"
  local expected_exit="$2"
  shift 2
  local case_dir="$RUN_ROOT/$name"
  mkdir -p "$case_dir"

  docker_run "$@" >"$case_dir/stdout.txt" 2>"$case_dir/stderr.txt"
  local rc=$?
  printf '%s\n' "$rc" >"$case_dir/exit_code.txt"
  printf '%q ' "$@" >"$case_dir/command.txt"
  printf '\n' >>"$case_dir/command.txt"

  if [ "$rc" -ne "$expected_exit" ]; then
    record "FAIL" "$name" "expected_exit=$expected_exit actual_exit=$rc"
    return
  fi
  if ! json_valid "$case_dir/stderr.txt" >"$case_dir/json_check.stdout" 2>"$case_dir/json_check.stderr"; then
    record "FAIL" "$name" "json audit invalid"
    return
  fi
  record "PASS" "$name" "exit=$rc json=valid"
}

printf 'run_id=%s\n' "$RUN_ID" >"$RUN_ROOT/replay_summary.txt"
printf 'image=%s\n' "$IMAGE" >>"$RUN_ROOT/replay_summary.txt"
printf 'root=%s\n' "$ROOT" >>"$RUN_ROOT/replay_summary.txt"

sg docker -c "docker image inspect '$IMAGE' --format '{{.Id}} {{.RepoDigests}}'" >"$RUN_ROOT/image_identity.txt" 2>"$RUN_ROOT/image_identity.stderr"
if [ "$?" -eq 0 ]; then
  record "PASS" "image_identity" "recorded"
else
  record "FAIL" "image_identity" "inspect failed"
fi

record_docker_metadata

run_case "allowed_python" 0 "$GUARD_IN_CONTAINER" --policy "$POLICY_IN_CONTAINER" /usr/local/bin/python3 --version
if json_query "$RUN_ROOT/allowed_python/stderr.txt" 'obj.get("decision") == "ALLOW"'; then
  record "PASS" "allowed_python_decision" "ALLOW decision recorded"
else
  record "FAIL" "allowed_python_decision" "missing ALLOW"
fi

cat > "$RUN_ROOT/blocked_renamed_rm.sh" <<'SH'
#!/bin/sh
set -eu
trap 'rm -f "$(dirname "$0")/renamed_rm_python3"' EXIT
cp /bin/rm "$(dirname "$0")/renamed_rm_python3"
chmod 755 "$(dirname "$0")/renamed_rm_python3"
/lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json "$(dirname "$0")/renamed_rm_python3" --version
SH
chmod +x "$RUN_ROOT/blocked_renamed_rm.sh"
run_case "blocked_renamed_rm" 126 /bin/sh /lab/proofs/sprint5_runs/$RUN_ID/blocked_renamed_rm.sh
if json_query "$RUN_ROOT/blocked_renamed_rm/stderr.txt" 'obj.get("reason") == "blocked_executable_identity"'; then
  record "PASS" "blocked_renamed_rm_reason" "identity block recorded"
else
  record "FAIL" "blocked_renamed_rm_reason" "missing identity block"
fi
if grep -q 'rm (GNU coreutils)' "$RUN_ROOT/blocked_renamed_rm/stdout.txt"; then
  record "FAIL" "blocked_renamed_rm_output" "renamed rm executed"
else
  record "PASS" "blocked_renamed_rm_output" "renamed rm did not execute"
fi

cat > "$RUN_ROOT/forge_stderr.py" <<'PY'
import sys
sys.stderr.write('{"event":"exec_decision","decision":"ALLOW","raw_exe":"/bin/rm","reason":"FORGED_IN_CONTAINER"}\n')
sys.stderr.flush()
PY
run_case "stderr_forgery_contained" 0 "$GUARD_IN_CONTAINER" --policy "$POLICY_IN_CONTAINER" /usr/local/bin/python3 /lab/proofs/sprint5_runs/$RUN_ID/forge_stderr.py
if json_query "$RUN_ROOT/stderr_forgery_contained/stderr.txt" 'obj.get("event") == "child_stderr" and "FORGED_IN_CONTAINER" in obj.get("data", "")' &&
   ! json_query "$RUN_ROOT/stderr_forgery_contained/stderr.txt" 'obj.get("event") == "exec_decision" and obj.get("reason") == "FORGED_IN_CONTAINER"'; then
  record "PASS" "stderr_forgery_contained_check" "forgery captured as child_stderr"
else
  record "FAIL" "stderr_forgery_contained_check" "forgery reached decision stream"
fi

sha256sum "$ROOT/src/usernotify_exec_guard.c" \
  "$ROOT/bin/usernotify_exec_guard" \
  "$ROOT/policy/integration/docker_python_slim.allow.json" \
  "$ROOT/scripts/integration/replay_sprint5_docker_guard.sh" >"$RUN_ROOT/sha256s.txt"

printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
printf 'run_root=%s\n' "$RUN_ROOT" | tee -a "$RUN_ROOT/replay_summary.txt"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
