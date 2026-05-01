# Sprint 7 Command Log - 2026-05-01

Scope: headless OpenHands agent loop with `usernotify_exec_guard` wrapping the pinned OpenHands runtime action server.

## Pre-registration

```text
git add proofs/SPRINT7_GATE_20260501.md
git commit -m "Pre-register Sprint 7 full OpenHands agent gate"
git push origin main
```

Pre-registration commit:

```text
a838f5b Pre-register Sprint 7 full OpenHands agent gate
```

## Dependency Setup

An ignored virtual environment was used because system Python is externally managed:

```text
python3 -m venv .venv-sprint7
.venv-sprint7/bin/pip install <OpenHands headless dependencies>
```

The venv is ignored by `.gitignore` and is not part of the committed lab evidence.

## Harness Iterations

Main replay command:

```text
./scripts/integration/replay_sprint7_headless_agent.sh
```

Early failures were preserved under `proofs/sprint7_runs/` and included missing Python dependencies, a BrowserGym version mismatch, runtime user mismatch, plugin startup scope, and DockerRuntime `init=True` mismatch.

Final passing run:

```text
proofs/sprint7_runs/sprint7-headless-agent-20260501T014104Z
pass=7 fail=0
```

## Guard Repair

Sprint 4 replay caught an `argv_total_count_capped` fidelity bug. The repair changed `capture_argv_json()` to mark `argv_total_count_capped=true` only when the scan reaches `MAX_ARGV_COUNT_SCAN` without observing the argv null terminator.

One local replay collision is also preserved: `proofs/sprint4_runs/sprint4-20260501T013852Z` failed with a `Text file busy` compile/run race caused by parallel replay execution during this sprint. It is not treated as a guard failure; the sequential post-repair Sprint 4 replay passed at `proofs/sprint4_runs/sprint4-20260501T014010Z`.

## Final Regression Commands

```text
./scripts/replay_sprint2_identity.sh
./scripts/replay_sprint4_audit_integrity.sh
./scripts/integration/replay_sprint5_docker_guard.sh
./scripts/integration/replay_sprint6_openhands_runtime.sh
./scripts/integration/replay_sprint6b_action_server.sh
./scripts/integration/replay_sprint7_headless_agent.sh
```

Final results:

```text
Sprint 2:  pass=12 fail=0
Sprint 4:  pass=22 fail=0
Sprint 5:  pass=11 fail=0
Sprint 6A: pass=13 fail=0
Sprint 6B: pass=15 fail=0
Sprint 7:  pass=7  fail=0
```

## Cleanup

The harness removes only the specific Sprint 7 runtime container name before starting:

```text
docker rm -f openhands-runtime-sprint7headless
```

No retained `/tmp` artifacts are part of this sprint.
