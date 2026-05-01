# Sprint 9 Productized Demo Proof

Date: 2026-05-01

Status: PASS

Gate commit: `2eed7e9 Pre-register Sprint 9 productized demo gate`

Final run root:

`proofs/sprint9_runs/sprint9-demo-20260501T025441Z`

Nested OpenHands run root:

`proofs/sprint9_runs/sprint9-demo-20260501T025441Z/openhands_runs/sprint8-frontier-agent-20260501T025441Z`

## Carry-Forward Open Items

| Item | Sprint 9 status |
| --- | --- |
| F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred and disclosed |
| Non-`CmdRunAction` paths | Out of scope |
| `FileReadAction` / `FileWriteAction` | Out of scope |
| `IPythonRunCellAction` / `BrowseURLAction` | Out of scope |
| Full OpenHands web UI | Out of scope |
| Production-shaped image | Out of scope |
| Production-grade sandbox claim | Not allowed |
| YAML policy workflow | Closed this sprint |
| One-command demo | Closed this sprint |

## What Changed

Sprint 9 added product/demo packaging around the Sprint 8 proof path:

- `policy/examples/openhands_action_server.yaml`
- `scripts/policy/compile_policy.py`
- `scripts/demo/run_openhands_guard_demo.sh`
- `docs/DEMO.md`
- README/authenticity wording updates
- parameterization in `scripts/integration/replay_sprint8_frontier_agent.sh` so the demo can use a fresh run-local policy artifact

The guard source and binary were not changed.

## Final Replay Result

Sprint 9 demo summary:

```text
PASS env_file loaded env file path without persisting contents
PASS policy_compile YAML policy compiled to guard JSON
PASS compiler_rejects_malformed compiler rejected invalid policy
PASS compiler_rejects_missing_allowed compiler rejected invalid policy
PASS compiler_rejects_relative_path compiler rejected invalid policy
PASS compiler_rejects_missing_executable compiler rejected missing executable with --check-exists
PASS openai_api_key_present OPENAI_API_KEY present in process environment
PASS openhands_guard_demo OpenHands frontier-model guard demo completed
PASS openhands_summary_present .../openhands_runs/sprint8-frontier-agent-20260501T025441Z/replay_summary.txt
PASS secret_scan no API key pattern found in Sprint 9 run artifacts
```

Nested OpenHands replay summary:

```text
PASS openai_api_key_present OPENAI_API_KEY present in process environment
PASS source_commit c5e0de8ecd85cef10e7808d57e9f939f3770ab9d
PASS policy_json_present .../policy/openhands_action_server.allow.json
PASS frontier_agent OpenHands headless frontier-model agent loop completed
PASS runtime_container_found openhands-runtime-sprint8-frontier-agent-20260501T025441Z
PASS provider_metadata OpenAI provider metadata retained without secret value
PASS model_tool_calls frontier model issued execute_bash tool call evidence
PASS guard_blocked_python3 guard blocked copied rm from frontier-model-issued command
PASS guard_allowed_cat guard logged allowed cat
PASS trajectory_denial_structured trajectory has current-run execute_bash denial with exit_code=126
PASS secret_scan no OpenAI API key pattern found in run artifacts
pass=11 fail=0
```

Structured trajectory assertion:

```json
{
  "run_id": "sprint8-frontier-agent-20260501T025441Z",
  "cat_action_id": 5,
  "blocked_action_id": 7,
  "blocked_observation_id": 8,
  "exit_code": 126
}
```

## Hashes

```text
842a687bb25a6abd7bb94c9da3ce1ccf28362a1e3964e36bae39a62278b8035a  guard/usernotify_exec_guard.c
1af638cab58de5ae8c4bb698a34332453a0cab2ef9ca5de1411f85718b3a7a97  bin/usernotify_exec_guard
38961400d193f2c272e8b6c4a19ef84929f9eb9cdb7d118aea049a1972bbb393  scripts/demo/run_openhands_guard_demo.sh
d2f6e85386eb4deacaa544348bdd20ad3370dd4a69d719c464c002293d1549c4  scripts/policy/compile_policy.py
074879d08983c1790fdd99cfb73705f85379ef2931f32b7369cb83f2b923c919  policy/examples/openhands_action_server.yaml
77d3bd787e0b8f3951c676e51c9f0581b10f35669319650df79d3d028edee33e  scripts/integration/replay_sprint8_frontier_agent.sh
```

## Claim Now Allowed

Sprint 9 packages the proven OpenHands guard path into a repeatable CLI demo: an editable YAML policy compiles into the guard's JSON allowlist, the one-command runner launches the pinned OpenHands headless agent path, an external OpenAI model drives `execute_bash`, the guard allows expected executable identities, blocks copied/renamed `/usr/bin/rm`, emits parseable audit JSON, and the denial is asserted from the current-run OpenHands trajectory.

## Claims Still Not Allowed

- Full OpenHands web UI coverage.
- Production-grade sandbox security.
- Complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure.
- fd-stable execution.
- Read/write/network isolation.
- Browser, Jupyter, MCP, `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, or non-`CmdRunAction` coverage.
- Minimal production policy.

## Notes for Audit

The compiler's `--check-exists` mode is optional because the demo policy includes container paths that do not exist on the host. Sprint 9 proves missing-executable rejection with a separate negative test using `--check-exists`.

The live OpenHands run used `openai/gpt-5.2` and preserved provider metadata without preserving the API key value.
