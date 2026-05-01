# Sprint 6 OpenHands Runtime One-File Proof

Date: 2026-05-01
Lab: `/home/blazingradar/agent-exec-guard-lab`
Gate commit: `fe5bd19 Pre-register Sprint 6 OpenHands runtime gate`
Posture: OpenHands runtime image probe, not full OpenHands app integration.

## Carry-Forward Open Items

| ID | Item | Sprint 6 status |
|---|---|---|
| F1 | Audit log forgery via shared fd 2 | Closed in Sprint 4; Sprint 5 replay preserved. |
| F2 | Supervisor killable by child via SIGTERM without final audit | Closed best-effort in Sprint 4; SIGKILL remains uncatchable. |
| F3 | Policy parser fail-open on malformed `allowed_executables` | Closed in Sprint 4; Sprint 4 replay preserved. |
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred and still disclosed. Sprint 6 does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. |
| F5 | `/proc/self/exe` resolves in supervisor namespace | Closed in Sprint 4; Sprint 4 replay preserved. |
| F6 | SHA256 helper fork+exec | Closed in Sprint 4 via AF_ALG; Sprint 4 replay preserved. |
| F7 | argv truncation metadata missing | Closed in Sprint 4; Sprint 4 replay preserved. |
| F8 | escaped quote handling in `policy_id` | Closed by Sprint 4 JSON parser; Sprint 4 replay preserved. |
| A1 | JSON parser nesting depth limit | Closed in Sprint 4 sweep; Sprint 4 replay preserved. |
| A2 | argv total count cap marker | Closed in Sprint 4 sweep; Sprint 4 replay preserved. |
| A3 | child stderr NUL preservation | Closed in Sprint 4 sweep; Sprint 4 replay preserved. |
| A4 | SIGKILL disclosure | Closed as disclosure in Sprint 4; SIGKILL remains uncatchable. |
| B5 | signal-handler async-signal-safety | Closed in Sprint 4 sweep; Sprint 4 replay preserved. |
| B6 | `\uXXXX` parsing limitation | Partially closed; surrogate pairs are intentionally rejected and disclosed. |
| Production sandboxing | Complete production-grade sandbox claim | Not allowed. |
| Full OpenHands app integration | LLM agent/app command path | Not yet claimed. Sprint 6A proves the pinned runtime image only. |

## Target Identity

Image:

```text
ghcr.io/openhands/runtime:1.6.0-nikolaik
```

Observed manifest-list digest:

```text
sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60
```

Observed amd64 child manifest digest:

```text
sha256:4959cef8059841fa5bf05fb1368d9ce5735d0ba94b2a3ceee335285e26529452
```

Docker image identity after pull:

```text
sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60 [ghcr.io/openhands/runtime@sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60] 2280016852
```

Raw provenance is preserved under:

```text
proofs/sprint6_provenance/
```

## What Changed

Sprint 6 added:

- `policy/integration/openhands_runtime.allow.json`
- `scripts/integration/replay_sprint6_openhands_runtime.sh`

No guard source changes were made.

## Replay Results

Latest Sprint 6A runtime replay:

```text
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint6_runs/sprint6-openhands-runtime-20260501T003348Z
pass=13 fail=0
```

Cases:

```text
PASS image_identity recorded
PASS docker_metadata_inspect HostConfig retained
PASS docker_securityopt_default HostConfig.SecurityOpt=None
PASS docker_proc_status_seccomp container reports Seccomp:2
PASS allowed_cat_workspace_file exit=0 json=valid
PASS allowed_cat_workspace_file_output workspace file read
PASS allowed_cat_workspace_file_decision ALLOW /usr/bin/cat recorded
PASS guarded_child_proc_status exit=0 json=valid
PASS guarded_child_nonewprivs guarded child reports NoNewPrivs:1
PASS guarded_child_seccomp guarded child reports Seccomp:2
PASS blocked_renamed_rm exit=126 json=valid
PASS blocked_renamed_rm_reason identity block recorded
PASS blocked_renamed_rm_output renamed rm did not execute
```

The one-file workspace proof used:

```text
proofs/sprint6_runs/sprint6-openhands-runtime-20260501T003348Z/workspace/input.txt
```

The retained Docker metadata includes:

```text
HostConfig.SecurityOpt=None
Seccomp: 2
NoNewPrivs: 0
/usr/local/bin/python3
/usr/bin/cat
/usr/bin/rm
```

The guarded child metadata includes:

```text
Name: cat
NoNewPrivs: 1
Seccomp: 2
```

## Regression Gates

```text
Sprint 2:
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260501T003132Z
pass=12 fail=0

Sprint 4:
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260501T003132Z
pass=22 fail=0

Sprint 5:
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T003133Z
pass=11 fail=0
```

## Claim Now Allowed

A local seccomp user-notify plus Landlock execution guard can run inside the pinned OpenHands runtime image, under Docker default seccomp, set `NoNewPrivs: 1` for the guarded child, read a one-file mounted workspace through an allowed executable, block a copied/renamed non-policy executable before it produces output, and emit parseable audit JSON while preserving Sprint 2, Sprint 4, and Sprint 5 regression gates.

## Claims Still Not Allowed

- No claim of full OpenHands app integration.
- No claim that an OpenHands LLM agent was supervised.
- No claim that F4 is fixed.
- No claim of production-grade sandboxing.
- No claim that this covers reads, writes, networking, or complete agent isolation.

## Next Gate

Sprint 6B should identify the actual OpenHands command-execution launch path and prove the guard can sit in that path. The acceptance bar should remain behavioral: the guarded path must run a normal allowed command and block a non-policy executable with retained audit JSON.
