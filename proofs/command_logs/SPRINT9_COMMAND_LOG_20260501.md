# Sprint 9 Command Log

Date: 2026-05-01

Scope: productized demo wrapper and editable policy config.

## Pre-Registration

```bash
git add proofs/SPRINT9_GATE_20260501.md
git commit -m "Pre-register Sprint 9 productized demo gate"
git push origin main
```

Result:

```text
2eed7e9 Pre-register Sprint 9 productized demo gate
```

## Implementation Checks

```bash
chmod +x scripts/demo/run_openhands_guard_demo.sh scripts/policy/compile_policy.py
bash -n scripts/demo/run_openhands_guard_demo.sh scripts/integration/replay_sprint8_frontier_agent.sh
python3 -m py_compile scripts/policy/compile_policy.py
scripts/policy/compile_policy.py policy/examples/openhands_action_server.yaml /tmp/sprint9_policy_compile_smoke.json
rm -f /tmp/sprint9_policy_compile_smoke.json
```

The `/tmp` smoke output was removed immediately and was not retained as a proof artifact.

## Final Sprint 9 Replay

```bash
./scripts/demo/run_openhands_guard_demo.sh \
  --env-file .env.local
```

Final run:

```text
proofs/sprint9_runs/sprint9-demo-20260501T025441Z
```

Nested OpenHands run:

```text
proofs/sprint9_runs/sprint9-demo-20260501T025441Z/openhands_runs/sprint8-frontier-agent-20260501T025441Z
```

Observed result:

```text
PASS openhands_guard_demo OpenHands frontier-model guard demo completed
PASS openhands_summary_present .../replay_summary.txt
PASS secret_scan no API key pattern found in Sprint 9 run artifacts
```

Nested OpenHands replay:

```text
pass=11 fail=0
```

## Post-Run Inspection

```bash
cat proofs/sprint9_runs/latest_demo.txt
cat proofs/sprint9_runs/sprint9-demo-20260501T025441Z/demo_summary.txt
cat proofs/sprint9_runs/sprint9-demo-20260501T025441Z/openhands_runs/sprint8-frontier-agent-20260501T025441Z/replay_summary.txt
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard scripts/demo/run_openhands_guard_demo.sh scripts/policy/compile_policy.py policy/examples/openhands_action_server.yaml scripts/integration/replay_sprint8_frontier_agent.sh
```

## Cleanup

Docker cleanup was performed after the run:

```bash
sg docker -c "docker rm -f openhands-runtime-sprint8-frontier-agent-20260501T025441Z"
```

No retained `/tmp` artifacts are part of Sprint 9.
