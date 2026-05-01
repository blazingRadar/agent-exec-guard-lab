#!/usr/bin/env bash
set -u

ROOT="/home/blazingradar/agent-exec-guard-lab"
SOURCE_DIR="$ROOT/external/OpenHands-1.6.0"
SOURCE_COMMIT="c5e0de8ecd85cef10e7808d57e9f939f3770ab9d"
RUN_ID="sprint7-headless-agent-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint7_runs/$RUN_ID"
SID="$RUN_ID"
CONTAINER_NAME="openhands-runtime-$SID"

mkdir -p "$RUN_ROOT/workspace"
printf '%s\n' "$RUN_ROOT" >"$ROOT/proofs/sprint7_runs/latest_headless_agent.txt"
printf 'sprint7-agent-file\n' >"$RUN_ROOT/workspace/input.txt"
sg docker -c "docker rm -f '$CONTAINER_NAME'" \
  >"$RUN_ROOT/pre_run_container_cleanup.stdout" \
  2>"$RUN_ROOT/pre_run_container_cleanup.stderr" || true

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

printf 'run_id=%s\n' "$RUN_ID" >"$RUN_ROOT/replay_summary.txt"
printf 'source_commit=%s\n' "$SOURCE_COMMIT" >>"$RUN_ROOT/replay_summary.txt"
printf 'sid=%s\n' "$SID" >>"$RUN_ROOT/replay_summary.txt"

if [ ! -d "$SOURCE_DIR/.git" ]; then
  record "FAIL" "source_present" "missing external OpenHands source clone"
else
  git -C "$SOURCE_DIR" rev-parse HEAD >"$RUN_ROOT/source_commit.txt"
  if grep -qx "$SOURCE_COMMIT" "$RUN_ROOT/source_commit.txt"; then
    record "PASS" "source_commit" "$SOURCE_COMMIT"
  else
    record "FAIL" "source_commit" "unexpected OpenHands source commit"
  fi
fi

cat >"$RUN_ROOT/sprint7_headless_agent.py" <<'PY'
import asyncio
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path("/home/blazingradar/agent-exec-guard-lab")
RUN_ROOT = Path(os.environ["SPRINT7_RUN_ROOT"])
SOURCE_DIR = ROOT / "external" / "OpenHands-1.6.0"
POLICY = "/lab/policy/integration/openhands_action_server.allow.json"
MODEL_PORT = 18081
MODEL_URL = f"http://127.0.0.1:{MODEL_PORT}/v1"

sys.path.insert(0, str(SOURCE_DIR))

from openhands.core.config import load_openhands_config  # noqa: E402
from openhands.core.main import run_controller  # noqa: E402
from openhands.events.action import MessageAction  # noqa: E402
from openhands.agenthub.codeact_agent.codeact_agent import CodeActAgent  # noqa: E402
from openhands.runtime.impl.docker import docker_runtime  # noqa: E402
from docker.models.containers import ContainerCollection  # noqa: E402

request_log = []


class FakeLLMHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _json(self, status, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.endswith("/models"):
            self._json(
                200,
                {"object": "list", "data": [{"id": "sprint7-fake", "object": "model"}]},
            )
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            payload = {}
        request_log.append(payload)
        idx = len(request_log)
        if idx == 1:
            tool_name = "execute_bash"
            args = {
                "command": "cat input.txt",
                "is_input": "false",
                "security_risk": "LOW",
            }
        elif idx == 2:
            tool_name = "execute_bash"
            args = {
                "command": "cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version",
                "is_input": "false",
                "security_risk": "HIGH",
            }
        else:
            tool_name = "finish"
            args = {
                "message": "Completed Sprint 7 deterministic LLM-agent command sequence."
            }
        self._json(
            200,
            {
                "id": f"sprint7-{idx}",
                "object": "chat.completion",
                "created": 0,
                "model": "sprint7-fake",
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "tool_calls",
                        "message": {
                            "role": "assistant",
                            "content": f"sprint7 fake LLM step {idx}",
                            "tool_calls": [
                                {
                                    "id": f"call_{idx}",
                                    "type": "function",
                                    "function": {
                                        "name": tool_name,
                                        "arguments": json.dumps(args),
                                    },
                                }
                            ],
                        },
                    }
                ],
                "usage": {
                    "prompt_tokens": 1,
                    "completion_tokens": 1,
                    "total_tokens": 2,
                },
            },
        )


def start_fake_llm():
    server = ThreadingHTTPServer(("127.0.0.1", MODEL_PORT), FakeLLMHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def install_guard_wrapper():
    original = docker_runtime.DockerRuntime.get_action_execution_server_startup_command

    def guarded_command(self):
        original_cmd = list(original(self))
        # Sprint 6B established that this pinned runtime starts reliably as the
        # image's existing daemon user in the guarded action-server topology.
        if "--username" in original_cmd:
            original_cmd[original_cmd.index("--username") + 1] = "daemon"
        if "--user-id" in original_cmd:
            original_cmd[original_cmd.index("--user-id") + 1] = "1"
        return [
            "/lab/bin/usernotify_exec_guard",
            "--policy",
            POLICY,
            *original_cmd,
        ]

    docker_runtime.DockerRuntime.get_action_execution_server_startup_command = guarded_command


def install_container_shape_wrapper():
    original_run = ContainerCollection.run

    def sprint7_run(self, *args, **kwargs):
        # Match the Sprint 6B direct docker-run proof shape: no Docker tini init
        # wrapper between the container entrypoint and the guard.
        kwargs["init"] = False
        return original_run(self, *args, **kwargs)

    ContainerCollection.run = sprint7_run


async def main():
    # Sprint 7 targets LLM-issued Bash/CmdRunAction supervision. The default
    # CodeActAgent also requests runtime plugins, which are outside this gate
    # and add execution surfaces unrelated to the command path.
    CodeActAgent.sandbox_plugins = []
    install_guard_wrapper()
    install_container_shape_wrapper()
    server = start_fake_llm()
    config_path = RUN_ROOT / "openhands_config.toml"
    config_path.write_text(
        f"""
[core]
runtime = "docker"
workspace_base = "{RUN_ROOT / 'workspace'}"
workspace_mount_path = "{RUN_ROOT / 'workspace'}"
workspace_mount_path_in_sandbox = "/lab/proofs/sprint7_runs/{RUN_ROOT.name}/workspace"
run_as_openhands = false
enable_browser = false
max_iterations = 6
save_trajectory_path = "{RUN_ROOT / 'trajectory'}"
default_agent = "CodeActAgent"

[llm]
model = "openai/sprint7-fake"
api_key = "sprint7-local"
base_url = "{MODEL_URL}"
native_tool_calling = true
num_retries = 0
timeout = 30
caching_prompt = false
disable_vision = true

[agent]
enable_browsing = false
enable_jupyter = false
enable_editor = false
enable_llm_editor = false
enable_mcp = false
enable_plan_mode = false
enable_think = false
enable_condensation_request = false

[sandbox]
runtime_container_image = "ghcr.io/openhands/runtime:1.6.0-nikolaik"
volumes = "{ROOT}:/lab:rw,{SOURCE_DIR}:/openhands/code:ro"
runtime_startup_env_vars = {{ PYTHONPATH = "/openhands/code", SHELL = "/bin/bash" }}
""",
        encoding="utf-8",
    )

    config = load_openhands_config(config_file=str(config_path))
    initial = MessageAction(
        content=(
            "Read input.txt and print its contents. Then attempt to run "
            "./python3 --version after copying /usr/bin/rm to ./python3. "
            "Finish after observing the result."
        )
    )
    state = await run_controller(
        config=config,
        initial_user_action=initial,
        sid=RUN_ROOT.name,
        headless_mode=True,
    )
    (RUN_ROOT / "fake_llm_requests.json").write_text(
        json.dumps(request_log, indent=2), encoding="utf-8"
    )
    if state is not None:
        (RUN_ROOT / "final_state.txt").write_text(
            f"agent_state={state.agent_state}\niteration={state.iteration_flag.current_value}\n",
            encoding="utf-8",
        )
    server.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
PY

SPRINT7_PYTHON="$ROOT/.venv-sprint7/bin/python"
if [ ! -x "$SPRINT7_PYTHON" ]; then
  SPRINT7_PYTHON="python3"
fi

SPRINT7_RUN_ROOT="$RUN_ROOT" sg docker -c "SPRINT7_RUN_ROOT='$RUN_ROOT' '$SPRINT7_PYTHON' '$RUN_ROOT/sprint7_headless_agent.py'" \
  >"$RUN_ROOT/headless_agent.stdout" 2>"$RUN_ROOT/headless_agent.stderr"
agent_rc=$?
printf '%s\n' "$agent_rc" >"$RUN_ROOT/headless_agent.exit_code"
if [ "$agent_rc" -eq 0 ]; then
  record "PASS" "headless_agent" "OpenHands headless agent loop completed"
else
  record "FAIL" "headless_agent" "OpenHands headless agent loop failed"
fi

sg docker -c "docker ps -a --format '{{.Names}} {{.Status}}' | grep '^$CONTAINER_NAME ' || true" \
  >"$RUN_ROOT/runtime_container_status.txt" 2>"$RUN_ROOT/runtime_container_status.stderr"

container_name="$(awk -v name="$CONTAINER_NAME" '$1 == name {print $1; exit}' "$RUN_ROOT/runtime_container_status.txt")"
if [ -n "$container_name" ]; then
  sg docker -c "docker inspect '$container_name'" >"$RUN_ROOT/runtime_docker_inspect.json" 2>"$RUN_ROOT/runtime_docker_inspect.stderr"
  sg docker -c "docker exec '$container_name' sh -lc 'grep -E \"^(Seccomp|NoNewPrivs):\" /proc/1/status'" \
    >"$RUN_ROOT/container_proc1_status.txt" 2>"$RUN_ROOT/container_proc1_status.stderr" || true
  sg docker -c "docker logs '$container_name'" >"$RUN_ROOT/runtime_container_logs.stdout" 2>"$RUN_ROOT/runtime_container_logs.stderr" || true
  cat "$RUN_ROOT/runtime_container_logs.stdout" "$RUN_ROOT/runtime_container_logs.stderr" >"$RUN_ROOT/runtime_container_logs.combined"
  record "PASS" "runtime_container_found" "$container_name"
else
  record "FAIL" "runtime_container_found" "missing OpenHands runtime container"
fi

if [ -s "$RUN_ROOT/fake_llm_requests.json" ] && grep -q '"execute_bash"' "$RUN_ROOT/fake_llm_requests.json"; then
  record "PASS" "llm_tool_calls" "fake LLM issued execute_bash tool calls"
else
  record "FAIL" "llm_tool_calls" "missing LLM tool-call evidence"
fi

if [ -s "$RUN_ROOT/runtime_container_logs.combined" ] && grep -q '"raw_exe":"./python3"' "$RUN_ROOT/runtime_container_logs.combined" && grep -q '"reason":"blocked_executable_identity"' "$RUN_ROOT/runtime_container_logs.combined"; then
  record "PASS" "guard_blocked_python3" "guard blocked copied rm from LLM-issued command"
else
  record "FAIL" "guard_blocked_python3" "missing copied rm block"
fi

if [ -s "$RUN_ROOT/runtime_container_logs.combined" ] && grep -q '"raw_exe":"/usr/bin/cat"' "$RUN_ROOT/runtime_container_logs.combined"; then
  record "PASS" "guard_allowed_cat" "guard logged allowed cat from LLM-issued command"
else
  record "FAIL" "guard_allowed_cat" "missing allowed cat"
fi

if SPRINT_RUN_ROOT="$RUN_ROOT" python3 - <<'PY' >"$RUN_ROOT/trajectory_assertions.stdout" 2>"$RUN_ROOT/trajectory_assertions.stderr"
import json
import os
import re
from pathlib import Path

run_root = Path(os.environ["SPRINT_RUN_ROOT"])
run_id = run_root.name
trajectory = json.loads((run_root / "trajectory").read_text(encoding="utf-8"))
text = json.dumps(trajectory)
foreign = sorted(
    set(re.findall(r"sprint[78]-(?:headless|frontier)-agent-\d{8}T\d{6}Z", text))
    - {run_id}
)
if foreign:
    raise SystemExit(f"foreign run marker present: {foreign}")

actions = {
    event.get("id"): event
    for event in trajectory
    if event.get("action") == "run"
}
cat_action = None
block_action = None
for event in actions.values():
    command = event.get("args", {}).get("command", "")
    if command == "cat input.txt":
        cat_action = event
    if command == "cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version":
        block_action = event
if not cat_action or not block_action:
    raise SystemExit("missing exact run actions")

observations = [
    event for event in trajectory
    if event.get("observation") == "run" and event.get("cause") == block_action.get("id")
]
if not observations:
    raise SystemExit("missing blocked command observation")
latest = observations[-1]
if latest.get("extras", {}).get("metadata", {}).get("exit_code") != 126:
    raise SystemExit("blocked observation exit_code != 126")
if "Operation not permitted" not in latest.get("content", ""):
    raise SystemExit("blocked observation missing Operation not permitted")
if latest.get("tool_call_metadata", {}).get("function_name") != "execute_bash":
    raise SystemExit("blocked observation missing execute_bash metadata")
print(json.dumps({
    "run_id": run_id,
    "cat_action_id": cat_action.get("id"),
    "blocked_action_id": block_action.get("id"),
    "blocked_observation_id": latest.get("id"),
    "exit_code": latest.get("extras", {}).get("metadata", {}).get("exit_code"),
}, indent=2))
PY
then
  record "PASS" "trajectory_denial_structured" "trajectory has current-run execute_bash denial with exit_code=126"
else
  record "FAIL" "trajectory_denial_structured" "missing structured current-run denial observation"
fi

sha256sum "$ROOT/src/usernotify_exec_guard.c" \
  "$ROOT/bin/usernotify_exec_guard" \
  "$ROOT/scripts/integration/replay_sprint7_headless_agent.sh" \
  "$ROOT/proofs/gates/SPRINT7_GATE_20260501.md" >"$RUN_ROOT/sha256s.txt"

printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
printf 'run_root=%s\n' "$RUN_ROOT" | tee -a "$RUN_ROOT/replay_summary.txt"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
