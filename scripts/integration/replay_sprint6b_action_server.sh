#!/usr/bin/env bash
set -u

ROOT="/home/blazingradar/agent-exec-guard-lab"
IMAGE="ghcr.io/openhands/runtime:1.6.0-nikolaik"
SOURCE_DIR="$ROOT/external/OpenHands-1.6.0"
SOURCE_URL="https://github.com/OpenHands/OpenHands.git"
SOURCE_TAG="1.6.0"
SOURCE_COMMIT="c5e0de8ecd85cef10e7808d57e9f939f3770ab9d"
RUN_ID="sprint6b-action-server-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint6b_runs/$RUN_ID"
CONTAINER_NAME="aeg-${RUN_ID}"
POLICY_IN_CONTAINER="/lab/policy/integration/openhands_action_server.allow.json"
WORKSPACE_IN_CONTAINER="/lab/proofs/sprint6b_runs/$RUN_ID/workspace"

mkdir -p "$RUN_ROOT/workspace"
printf '%s\n' "$RUN_ROOT" >"$ROOT/proofs/sprint6b_runs/latest_action_server.txt"
printf 'sprint6b-action-server-file\n' >"$RUN_ROOT/workspace/input.txt"

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

json_valid_lines() {
  local path="$1"
  python3 - "$path" <<'PY'
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
    raise SystemExit("no JSON lines")
PY
}

json_response_query() {
  local path="$1"
  local expr="$2"
  python3 - "$path" "$expr" <<'PY'
import json
import sys

path, expr = sys.argv[1:3]
obj = json.loads(open(path, "r", encoding="utf-8").read())
if eval(expr, {}, {"obj": obj}):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

ensure_source() {
  mkdir -p "$ROOT/external"
  if [ ! -d "$SOURCE_DIR/.git" ]; then
    git clone --depth 1 --branch "$SOURCE_TAG" --filter=blob:none "$SOURCE_URL" "$SOURCE_DIR" \
      >"$RUN_ROOT/source_clone.stdout" 2>"$RUN_ROOT/source_clone.stderr"
  fi
  git -C "$SOURCE_DIR" rev-parse HEAD >"$RUN_ROOT/source_commit.txt"
  if grep -qx "$SOURCE_COMMIT" "$RUN_ROOT/source_commit.txt"; then
    record "PASS" "source_commit" "$SOURCE_COMMIT"
  else
    record "FAIL" "source_commit" "unexpected OpenHands source commit"
  fi
}

record_image_identity() {
  sg docker -c "docker image inspect '$IMAGE' --format '{{.Id}} {{.RepoDigests}} {{.Size}}'" \
    >"$RUN_ROOT/image_identity.txt" 2>"$RUN_ROOT/image_identity.stderr"
  if [ "$?" -eq 0 ]; then
    record "PASS" "image_identity" "recorded"
  else
    record "FAIL" "image_identity" "inspect failed"
  fi
}

start_server() {
  sg docker -c "docker rm -f '$CONTAINER_NAME' >/dev/null 2>&1 || true"
  sg docker -c "docker run -d --name '$CONTAINER_NAME' \
    -v '$ROOT:/lab:rw' \
    -v '$SOURCE_DIR:/openhands/code:ro' \
    -w /openhands/code \
    -e PYTHONPATH=/openhands/code \
    '$IMAGE' \
    /lab/bin/usernotify_exec_guard \
    --policy '$POLICY_IN_CONTAINER' \
    /openhands/micromamba/bin/micromamba run -n openhands poetry run python -u -m openhands.runtime.action_execution_server 30000 \
    --working-dir '$WORKSPACE_IN_CONTAINER' \
    --username daemon \
    --user-id 1 \
    --no-enable-browser" >"$RUN_ROOT/docker_run.stdout" 2>"$RUN_ROOT/docker_run.stderr"
  local rc=$?
  printf '%s\n' "$rc" >"$RUN_ROOT/docker_run.exit_code"
  if [ "$rc" -eq 0 ]; then
    record "PASS" "docker_run" "container started"
  else
    record "FAIL" "docker_run" "container start failed"
  fi
}

record_docker_metadata() {
  sg docker -c "docker inspect '$CONTAINER_NAME'" >"$RUN_ROOT/docker_inspect.json" 2>"$RUN_ROOT/docker_inspect.stderr"
  if [ "$?" -eq 0 ]; then
    record "PASS" "docker_inspect" "recorded"
  else
    record "FAIL" "docker_inspect" "failed"
  fi

  python3 - "$RUN_ROOT/docker_inspect.json" >"$RUN_ROOT/hostconfig_securityopt.txt" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(repr(data[0].get("HostConfig", {}).get("SecurityOpt")))
PY
  if grep -qx 'None' "$RUN_ROOT/hostconfig_securityopt.txt"; then
    record "PASS" "docker_securityopt_default" "HostConfig.SecurityOpt=None"
  else
    record "FAIL" "docker_securityopt_default" "HostConfig.SecurityOpt not default"
  fi

  sg docker -c "docker exec '$CONTAINER_NAME' /bin/sh -lc 'grep -E \"^(Seccomp|NoNewPrivs):\" /proc/self/status'" \
    >"$RUN_ROOT/container_proc_status.txt" 2>"$RUN_ROOT/container_proc_status.stderr"
  if grep -q '^Seccomp:[[:space:]]*2$' "$RUN_ROOT/container_proc_status.txt"; then
    record "PASS" "docker_proc_status_seccomp" "container reports Seccomp:2"
  else
    record "FAIL" "docker_proc_status_seccomp" "container Seccomp metadata missing"
  fi
}

write_client_scripts() {
  cat >"$RUN_ROOT/alive_probe.py" <<'PY'
import urllib.request
with urllib.request.urlopen("http://127.0.0.1:30000/alive", timeout=3) as resp:
    print(resp.status, resp.read().decode())
PY
  cat >"$RUN_ROOT/send_action.py" <<'PY'
import json
import sys
import urllib.request

command = sys.argv[1]
payload = {
    "action": {
        "action": "run",
        "args": {
            "command": command,
            "is_input": False,
            "blocking": False,
            "is_static": False,
        },
    }
}
req = urllib.request.Request(
    "http://127.0.0.1:30000/execute_action",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=45) as resp:
    sys.stdout.write(resp.read().decode())
PY
}

wait_for_alive() {
  local i
  for i in $(seq 1 45); do
    sg docker -c "docker exec '$CONTAINER_NAME' /usr/local/bin/python3 /lab/proofs/sprint6b_runs/$RUN_ID/alive_probe.py" \
      >"$RUN_ROOT/alive_probe.stdout" 2>"$RUN_ROOT/alive_probe.stderr"
    if [ "$?" -eq 0 ]; then
      record "PASS" "alive_probe" "server returned /alive"
      return
    fi
    sleep 1
  done
  record "FAIL" "alive_probe" "server did not return /alive"
}

run_action_case() {
  local name="$1"
  local command="$2"
  sg docker -c "docker exec '$CONTAINER_NAME' /usr/local/bin/python3 /lab/proofs/sprint6b_runs/$RUN_ID/send_action.py '$command'" \
    >"$RUN_ROOT/${name}.response.json" 2>"$RUN_ROOT/${name}.stderr"
  local rc=$?
  printf '%s\n' "$rc" >"$RUN_ROOT/${name}.exit_code"
  if [ "$rc" -eq 0 ]; then
    record "PASS" "$name" "HTTP action returned"
  else
    record "FAIL" "$name" "HTTP action failed"
  fi
}

record_logs() {
  sg docker -c "docker logs '$CONTAINER_NAME'" >"$RUN_ROOT/container_logs.stdout" 2>"$RUN_ROOT/container_logs.stderr" || true
  cat "$RUN_ROOT/container_logs.stdout" "$RUN_ROOT/container_logs.stderr" >"$RUN_ROOT/container_logs.combined"
  if json_valid_lines "$RUN_ROOT/container_logs.combined" >"$RUN_ROOT/container_logs_json_check.stdout" 2>"$RUN_ROOT/container_logs_json_check.stderr"; then
    record "PASS" "container_logs_json" "guard audit lines parse"
  else
    record "FAIL" "container_logs_json" "guard audit JSON invalid"
  fi
}

cleanup_container() {
  sg docker -c "docker rm -f '$CONTAINER_NAME' >/dev/null 2>&1 || true"
}

printf 'run_id=%s\n' "$RUN_ID" >"$RUN_ROOT/replay_summary.txt"
printf 'image=%s\n' "$IMAGE" >>"$RUN_ROOT/replay_summary.txt"
printf 'source_commit=%s\n' "$SOURCE_COMMIT" >>"$RUN_ROOT/replay_summary.txt"

ensure_source
record_image_identity
write_client_scripts
start_server
record_docker_metadata
wait_for_alive

run_action_case "action_allowed_cat" "cat input.txt"
if json_response_query "$RUN_ROOT/action_allowed_cat.response.json" 'obj.get("success") is True and obj.get("extras", {}).get("metadata", {}).get("exit_code") == 0 and obj.get("content") == "sprint6b-action-server-file"'; then
  record "PASS" "action_allowed_cat_result" "workspace file read via /execute_action"
else
  record "FAIL" "action_allowed_cat_result" "unexpected allowed action response"
fi

run_action_case "action_guarded_proc_status" "cat /proc/self/status"
if json_response_query "$RUN_ROOT/action_guarded_proc_status.response.json" 'any(line.startswith("NoNewPrivs:") and line.split()[-1] == "1" for line in obj.get("content", "").splitlines()) and any(line.startswith("Seccomp:") and line.split()[-1] == "2" for line in obj.get("content", "").splitlines())'; then
  record "PASS" "action_guarded_proc_status_result" "guarded action child reports NoNewPrivs:1 and Seccomp:2"
else
  record "FAIL" "action_guarded_proc_status_result" "guarded action child metadata missing"
fi

run_action_case "action_block_renamed_rm" "cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version"
if json_response_query "$RUN_ROOT/action_block_renamed_rm.response.json" 'obj.get("success") is False and obj.get("extras", {}).get("metadata", {}).get("exit_code") == 126 and "Operation not permitted" in obj.get("content", "")'; then
  record "PASS" "action_block_renamed_rm_result" "renamed rm blocked via /execute_action"
else
  record "FAIL" "action_block_renamed_rm_result" "unexpected blocked action response"
fi

record_logs
if grep -q '"reason":"blocked_executable_identity".*"raw_exe":"./python3"' "$RUN_ROOT/container_logs.combined"; then
  record "PASS" "guard_log_blocked_python3" "guard logged copied rm block"
else
  record "FAIL" "guard_log_blocked_python3" "missing copied rm block log"
fi

sha256sum "$ROOT/src/usernotify_exec_guard.c" \
  "$ROOT/bin/usernotify_exec_guard" \
  "$ROOT/policy/integration/openhands_action_server.allow.json" \
  "$ROOT/scripts/integration/replay_sprint6b_action_server.sh" \
  "$ROOT/proofs/gates/SPRINT6B_GATE_20260501.md" >"$RUN_ROOT/sha256s.txt"

cleanup_container

printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
printf 'run_root=%s\n' "$RUN_ROOT" | tee -a "$RUN_ROOT/replay_summary.txt"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
