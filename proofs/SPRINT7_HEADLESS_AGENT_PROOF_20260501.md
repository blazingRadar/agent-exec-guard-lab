# Sprint 7 Headless OpenHands Agent Proof - 2026-05-01

## Carry-forward Open Items

| Item | Status |
|---|---|
| F1 audit forgery via shared fd 2 | Closed in Sprint 4; preserved by Sprint 4 replay pass=22 fail=0 |
| F2 best-effort signal audit | Closed for SIGTERM/INT/HUP; SIGKILL remains uncatchable by design |
| F3/F8 policy parser fail-open / escaped policy_id | Closed in Sprint 4; preserved by Sprint 4 replay |
| F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred; Landlock reduces practical non-policy replacement risk but does not eliminate all allowed-path race classes |
| F5 `/proc/self/exe` child-context resolution | Closed in Sprint 4; preserved by Sprint 4 replay |
| F6 helper `sha256sum` execution | Closed in Sprint 4; AF_ALG path retained |
| F7 argv truncation metadata | Closed again in this sprint after replay caught a count-cap fidelity bug |
| A1 JSON parser depth limit | Closed in Sprint 4 |
| A2 argv count cap marker | Closed in Sprint 4; repaired in this sprint |
| A3 NUL-preserving child stderr | Closed in Sprint 4 |
| A4 SIGKILL disclosure | Disclosed; cannot be caught |
| B5 async-signal-safe signal handler | Closed in Sprint 4 |
| B6 `\uXXXX` JSON escape handling | Closed for BMP escapes; surrogate pairs remain unsupported/disclosed |
| Non-CmdRunAction surfaces | Out of scope for Sprint 7 |
| Full OpenHands web UI | Out of scope for Sprint 7 |
| External frontier LLM behavior | Out of scope for Sprint 7 |

## Result

Sprint 7 passes as a headless OpenHands agent-loop proof.

Final run:

```text
proofs/sprint7_runs/sprint7-headless-agent-20260501T014104Z
pass=7 fail=0
agent_state=AgentState.FINISHED
iteration=6
```

The final run proves that a pinned OpenHands 1.6.0 `CodeActAgent` loop, driven by a local OpenAI-compatible fake LLM endpoint, can issue real `execute_bash` tool calls through OpenHands' Docker runtime action server while the action server is wrapped by `usernotify_exec_guard`.

## Evidence

Pinned OpenHands source:

```text
c5e0de8ecd85cef10e7808d57e9f939f3770ab9d
```

Final artifact hashes:

```text
842a687bb25a6abd7bb94c9da3ce1ccf28362a1e3964e36bae39a62278b8035a  guard/usernotify_exec_guard.c
1af638cab58de5ae8c4bb698a34332453a0cab2ef9ca5de1411f85718b3a7a97  bin/usernotify_exec_guard
5a59408bbed7b7b411a111e54bfacb00080312214adaa6191a4e47247949f035  scripts/integration/replay_sprint7_headless_agent.sh
1593422da8001408820aef3d116d65ed7263ade1d86f0fd9f6edc24165d606a1  proofs/SPRINT7_GATE_20260501.md
```

Container metadata retained in `runtime_docker_inspect.json`:

```text
HostConfig.SecurityOpt=None
HostConfig.Init=False
image=sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60
```

The guarded command was:

```text
/lab/bin/usernotify_exec_guard --policy /lab/policy/integration/openhands_action_server.allow.json /openhands/micromamba/bin/micromamba run -n openhands poetry run python -u -m openhands.runtime.action_execution_server <port> --working-dir /lab/proofs/sprint7_runs/sprint7-headless-agent-20260501T014104Z/workspace --username daemon --user-id 1 --no-enable-browser
```

The fake LLM request log and OpenHands trajectory both show `execute_bash` tool calls. The trajectory records:

```text
sprint7-agent-file
bash: ./python3: Operation not permitted
```

The guard audit stream records:

```text
ALLOW raw_exe="/usr/bin/cat" argv=["cat","input.txt"]
BLOCK raw_exe="./python3" reason="blocked_executable_identity"
```

The blocked `./python3` was a copied `/usr/bin/rm`, so the Sprint 2 identity property survived the actual OpenHands agent loop.

## Implementation Notes

Sprint 7 uses a local deterministic fake LLM endpoint, not an external model. This is intentional: the sprint tests the OpenHands agent/tool/runtime path deterministically, not model quality or prompt reliability.

The harness patches three runtime details without editing OpenHands source:

1. Wraps `DockerRuntime.get_action_execution_server_startup_command()` with the guard command.
2. Uses the known-good Sprint 6B daemon user path for the action server.
3. Disables DockerRuntime's `init=True` wrapper to match the direct Sprint 6B Docker proof shape.

The harness also clears `CodeActAgent.sandbox_plugins` for this proof. Sprint 7 is a Bash/CmdRunAction execution-boundary proof; Jupyter, browser, file action, and plugin execution surfaces are separate surfaces and remain out of scope.

## Repair Made During Sprint 7

Sprint 4 replay initially caught an `argv_total_count_capped` fidelity regression. The guard counted real arguments correctly but could mark `argv_total_count_capped=true` by probing beyond the argv null terminator into adjacent environment memory.

This was fixed by tracking whether the argv null terminator was observed during the scan. Sprint 4 then replayed cleanly at pass=22 fail=0.

## Regression Runs

Final regression set after the Sprint 7 guard repair:

```text
Sprint 2:  pass=12 fail=0  proofs/sprint2_runs/sprint2-20260501T014017Z
Sprint 4:  pass=22 fail=0  proofs/sprint4_runs/sprint4-20260501T014010Z
Sprint 5:  pass=11 fail=0  proofs/sprint5_runs/sprint5-docker-20260501T014022Z
Sprint 6A: pass=13 fail=0  proofs/sprint6_runs/sprint6-openhands-runtime-20260501T014029Z
Sprint 6B: pass=15 fail=0  proofs/sprint6b_runs/sprint6b-action-server-20260501T014039Z
Sprint 7:  pass=7  fail=0  proofs/sprint7_runs/sprint7-headless-agent-20260501T014104Z
```

## Failed Runs Preserved

Sprint 7 preserves the failed runs that led to the final shape. The failures were dependency resolution, OpenHands runtime-shape mismatches, plugin startup scope, and DockerRuntime `init=True` mismatch with the Sprint 6B proof shape.

Representative failed runs:

```text
proofs/sprint7_runs/sprint7-headless-agent-20260501T012323Z
proofs/sprint7_runs/sprint7-headless-agent-20260501T012653Z
proofs/sprint7_runs/sprint7-headless-agent-20260501T012921Z
proofs/sprint7_runs/sprint7-headless-agent-20260501T013134Z
proofs/sprint7_runs/sprint7-headless-agent-20260501T013546Z
```

These are not deleted because they show the integration path and prevent a false "worked first try" story.

## Claim Now Allowed

A pinned OpenHands 1.6.0 headless `CodeActAgent` loop can be driven by an OpenAI-compatible LLM endpoint into issuing real `execute_bash` tool calls through the OpenHands Docker runtime action server, while a seccomp user-notify plus Landlock guard wraps that action server, allows an approved `/usr/bin/cat input.txt`, blocks a copied `/usr/bin/rm` renamed to `./python3`, returns `Operation not permitted` to the OpenHands trajectory, and preserves Sprint 2/4/5/6A/6B regression gates.

## Claims Still Not Allowed

- Full OpenHands web UI proof.
- External frontier model proof.
- Production sandbox claim.
- Complete Linux sandbox claim.
- Non-CmdRunAction coverage.
- FileRead/FileWrite/IPython/BrowseURL/MCP endpoint coverage.
- Full F4 TOCTOU closure.
- Minimal allowlist claim; the OpenHands startup policy is intentionally broad enough to boot the pinned runtime.
- Jupyter/plugin execution supervision claim.

## Post-Audit Cleanup

Independent Sprint 7 auditors found that the original harness used a fixed OpenHands `sid`, which allowed reruns to accumulate state under `~/.openhands/sessions/`. The cleanup in `proofs/SPRINT7_8_CLEANUP_20260501.md` changes Sprint 7 to use a unique run-ID `sid`, dynamic runtime container names, and structured current-run trajectory assertions instead of broad `grep -R "Operation not permitted"` checks.

Cleanup verification:

```text
proofs/sprint7_runs/sprint7-headless-agent-20260501T023918Z  pass=7 fail=0
proofs/sprint7_runs/sprint7-headless-agent-20260501T023939Z  pass=7 fail=0
```
