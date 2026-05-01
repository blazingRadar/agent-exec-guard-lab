# Sprint 6 Command Log

Date: 2026-05-01
Lab: `/home/blazingradar/agent-exec-guard-lab`

## Pre-Registration

Sprint 6 gate was committed and pushed before implementation:

```text
fe5bd19 Pre-register Sprint 6 OpenHands runtime gate
```

## Runtime Pull

```bash
sg docker -c "docker pull ghcr.io/openhands/runtime:1.6.0-nikolaik"
```

Result:

```text
run_root=proofs/sprint6_runs/sprint6-openhands-runtime-20260501T002922Z
rc=0
Digest: sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60
Status: Downloaded newer image for ghcr.io/openhands/runtime:1.6.0-nikolaik
```

## Manual Sanity Probe

Before writing the replay harness, the guard was manually run inside the runtime image:

```bash
sg docker -c "docker run --rm -v '$PWD:/lab:rw' -w /lab ghcr.io/openhands/runtime:1.6.0-nikolaik /lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json /usr/local/bin/python3 --version"
```

Result:

```text
rc=0
Python 3.12.13
```

The manual probe artifacts are preserved at:

```text
proofs/sprint6_runs/manual_runtime_guard.stdout
proofs/sprint6_runs/manual_runtime_guard.stderr
```

## Replay Commands

Sprint 6A OpenHands runtime replay:

```bash
./scripts/integration/replay_sprint6_openhands_runtime.sh
```

Latest clean result:

```text
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint6_runs/sprint6-openhands-runtime-20260501T003348Z
pass=13 fail=0
```

Regression gates:

```bash
./scripts/replay_sprint2_identity.sh
./scripts/replay_sprint4_audit_integrity.sh
./scripts/integration/replay_sprint5_docker_guard.sh
```

Clean results:

```text
Sprint 2: pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260501T003132Z

Sprint 4: pass=22 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260501T003132Z

Sprint 5: pass=11 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T003133Z
```

## Hashes

```text
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
f7b64cedb93711cc796b12bddb1d3331aedf45fec5ee146f4135be1f95c068e2  policy/integration/openhands_runtime.allow.json
32af2719b818c54c5d1a789cc3e3d72bc110bcbdca0fd0a38a61955c9d21e03b  scripts/integration/replay_sprint6_openhands_runtime.sh
3e0cba0452c92cae0dbb48800f3b983e1ed280ea6e1fb0ef13d230d2dfd1e3d4  proofs/SPRINT6_GATE_20260501.md
```

## Notes

No retained `/tmp` artifacts were used for Sprint 6.
