# Sprint 5 Docker Container Proof

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: integration reality check, not F4 architecture work.

## Carry-Forward Open Items

| ID | Item | Sprint 5 status |
|---|---|---|
| F1 | Audit log forgery via shared fd 2 | Closed in Sprint 4; preserved by Sprint 5 Docker replay. |
| F2 | Supervisor killable by child via SIGTERM without final audit | Closed best-effort in Sprint 4; no new Sprint 5 regression. SIGKILL remains uncatchable. |
| F3 | Policy parser fail-open on malformed `allowed_executables` | Closed in Sprint 4; no new Sprint 5 regression. |
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred and still disclosed. Sprint 5 does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. |
| F5 | `/proc/self/exe` resolves in supervisor namespace | Closed in Sprint 4; no new Sprint 5 regression. |
| F6 | SHA256 helper fork+exec | Closed in Sprint 4 via AF_ALG; no new Sprint 5 regression. |
| F7 | argv truncation metadata missing | Closed in Sprint 4; no new Sprint 5 regression. |
| F8 | escaped quote handling in `policy_id` | Closed by Sprint 4 JSON parser; no new Sprint 5 regression. |
| A1 | JSON parser nesting depth limit | Closed in Sprint 4 sweep; no new Sprint 5 regression. |
| A2 | argv total count cap marker | Closed in Sprint 4 sweep; no new Sprint 5 regression. |
| A3 | child stderr NUL preservation | Closed in Sprint 4 sweep; no new Sprint 5 regression. |
| A4 | SIGKILL disclosure | Closed as disclosure in Sprint 4; SIGKILL remains uncatchable. |
| B5 | signal-handler async-signal-safety | Closed in Sprint 4 sweep; no new Sprint 5 regression. |
| B6 | `\uXXXX` parsing limitation | Partially closed in Sprint 4 sweep; surrogate pairs are intentionally rejected and disclosed. |
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
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T002321Z
pass=11 fail=0
```

Cases:

```text
PASS image_identity recorded
PASS docker_metadata_inspect HostConfig retained
PASS docker_securityopt_default HostConfig.SecurityOpt=None
PASS docker_proc_status_seccomp container reports Seccomp:2
PASS allowed_python exit=0 json=valid
PASS allowed_python_decision ALLOW decision recorded
PASS blocked_renamed_rm exit=126 json=valid
PASS blocked_renamed_rm_reason identity block recorded
PASS blocked_renamed_rm_output renamed rm did not execute
PASS stderr_forgery_contained exit=0 json=valid
PASS stderr_forgery_contained_check forgery captured as child_stderr
```

Positive Docker-seccomp metadata is retained in:

```text
proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/
proofs/sprint5_runs/sprint5-docker-20260501T002321Z/docker_metadata/
```

The retained metadata includes:

```text
HostConfig.SecurityOpt=None
Seccomp: 2
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
- `proofs/sprint5_runs/sprint5-docker-20260501T000055Z` and `proofs/sprint5_runs/sprint5-docker-20260501T002113Z`: clean Docker passes superseded by the metadata-retaining final run.
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
