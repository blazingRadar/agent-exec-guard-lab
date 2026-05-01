# Sprint 5 Docker Container Proof

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: integration reality check, not F4 architecture work.

## Carry-Forward Open Items

| ID | Item | Sprint 5 status |
|---|---|---|
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred and still disclosed. Sprint 5 does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. |
| OpenHands full runtime | Prove against the pinned OpenHands command runtime image | Not yet claimed. Runtime image was identified but not pulled into this proof. |
| Production-grade sandboxing | Complete sandbox claim | Not allowed. Sprint 5 proves a local container execution boundary only. |

## What Changed

Sprint 5 added a Docker replay harness and a container policy:

- `scripts/integration/replay_sprint5_docker_guard.sh`
- `policy/integration/docker_python_slim.allow.json`

The harness runs the existing guard inside a Docker container using Docker's default seccomp profile. It does not require `--security-opt seccomp=unconfined`.

## Target Identity

Container image used for the runnable proof:

```text
python:3.12-slim
sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286
python@sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286
```

Pinned OpenHands target recorded for the next phase:

```text
OpenHands/OpenHands release: 1.6.0
release date: 2026-03-30T16:01:39Z
app image: docker.openhands.dev/openhands/openhands:1.6.0
app manifest digest: sha256:5c0dc26f467bf8e47a6e76308edb7a30af4084b17e23a3460b5467008b12111b
runtime image: ghcr.io/openhands/runtime:1.6.0-nikolaik
runtime amd64 digest: sha256:4959cef8059841fa5bf05fb1368d9ce5735d0ba94b2a3ceee335285e26529452
```

The OpenHands runtime image is about 2.28 GB compressed for amd64, so this sprint did not pull it as part of the first container proof.

## Replay Results

Latest Sprint 5 Docker replay:

```text
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T000055Z
pass=6 fail=0
```

Cases:

```text
PASS image_identity recorded
PASS allowed_python exit=0 json=valid
PASS blocked_renamed_rm exit=126 json=valid
PASS blocked_renamed_rm_output renamed rm did not execute
PASS stderr_forgery_contained exit=0 json=valid
PASS stderr_forgery_contained_check forgery captured as child_stderr
```

Regression gates after Sprint 5:

```text
Sprint 2 replay:
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T235805Z
pass=12 fail=0

Sprint 4 replay:
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260430T235809Z
pass=22 fail=0
```

## Preserved Failed Runs

Two failed or superseded observations are intentionally preserved:

- `proofs/sprint5_runs/sprint5-docker-20260430T235602Z`: first Docker harness attempt failed due shell quoting bugs.
- `proofs/sprint5_runs/sprint5-docker-20260430T235637Z` and `proofs/sprint5_runs/sprint5-docker-20260430T235835Z`: clean Docker passes superseded by the final run after the harness was tightened to avoid retaining the copied `/bin/rm` fixture.
- `proofs/sprint2_runs/sprint2-20260430T235747Z` and `proofs/sprint4_runs/sprint4-20260430T235748Z`: false replay failures caused by running Sprint 2 and Sprint 4 harnesses in parallel while both compiled to `bin/usernotify_exec_guard`. Sequential reruns passed.

## Claim Now Allowed

A local seccomp user-notify plus Landlock execution guard can run inside a Docker container under Docker's default seccomp profile, allow an approved container executable, block a copied non-policy executable before it runs, and preserve the Sprint 4 audit-forgery boundary by demoting child-written JSON to `child_stderr`.

## Claims Still Not Allowed

- No claim that this is integrated with OpenHands yet.
- No claim that the pinned OpenHands runtime image has been pulled or exercised.
- No claim that F4 is fixed.
- No claim of production-grade sandboxing.
- No claim that this covers reads, writes, networking, or complete agent isolation.

## Next Gate

Sprint 5B should run the same boundary against the pinned OpenHands runtime image or the actual OpenHands command-execution path. The acceptance criterion is not "OpenHands launches"; it is that the guard is demonstrably in the command-execution path and blocks a non-policy executable with parseable audit output.
