# Sprint 6 Gate: OpenHands Runtime One-File Probe

Date: 2026-05-01
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: pre-registered gate. This file must be committed and pushed before Sprint 6 implementation starts.

## Goal

Prove the smallest real OpenHands-runtime path before attempting full OpenHands app integration:

1. Pull or run the pinned OpenHands runtime image.
2. Mount one tiny test workspace/file.
3. Run the existing guard against commands inside that runtime container.
4. Preserve Docker/runtime metadata and audit JSON.

This is still not a full OpenHands app proof. It is the bridge between Sprint 5A Docker feasibility and a later full OpenHands command-path integration.

## Target

```text
runtime image: ghcr.io/openhands/runtime:1.6.0-nikolaik
runtime amd64 digest from Sprint 5 provenance: sha256:4959cef8059841fa5bf05fb1368d9ce5735d0ba94b2a3ceee335285e26529452
```

## Carry-Forward Open Items

| ID | Item | Sprint 6 status before work |
|---|---|---|
| F1 | Audit log forgery via shared fd 2 | Closed in Sprint 4; must not regress. |
| F2 | Supervisor killable by child via SIGTERM without final audit | Closed best-effort in Sprint 4; SIGKILL remains uncatchable. |
| F3 | Policy parser fail-open on malformed `allowed_executables` | Closed in Sprint 4; must not regress. |
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred. Sprint 6 does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. Must be disclosed. |
| F5 | `/proc/self/exe` resolves in supervisor namespace | Closed in Sprint 4; must not regress. |
| F6 | SHA256 helper fork+exec | Closed in Sprint 4 via AF_ALG; must not regress. |
| F7 | argv truncation metadata missing | Closed in Sprint 4; must not regress. |
| F8 | escaped quote handling in `policy_id` | Closed by Sprint 4 JSON parser; must not regress. |
| A1 | JSON parser nesting depth limit | Closed in Sprint 4 sweep; must not regress. |
| A2 | argv total count cap marker | Closed in Sprint 4 sweep; must not regress. |
| A3 | child stderr NUL preservation | Closed in Sprint 4 sweep; must not regress. |
| A4 | SIGKILL disclosure | Closed as disclosure in Sprint 4; SIGKILL remains uncatchable. |
| B5 | signal-handler async-signal-safety | Closed in Sprint 4 sweep; must not regress. |
| B6 | `\uXXXX` parsing limitation | Partially closed; surrogate pairs are intentionally rejected and disclosed. |
| Sprint 5A | Docker feasibility proof | Closed as `python:3.12-slim` proof; Sprint 6 must prove OpenHands runtime image specifically. |
| Production sandboxing | Complete production-grade sandbox claim | Not allowed. |

## Acceptance Criteria

Sprint 6A passes only if all of these are true:

1. The pinned OpenHands runtime image is pulled or run, and its digest is recorded.
2. Docker metadata is preserved:
   - `HostConfig.SecurityOpt`
   - in-container `/proc/self/status` `Seccomp:`
3. A one-file mounted workspace is created and preserved.
4. At least one allowed command reads or inspects the workspace file through the guard.
5. A copied/renamed non-policy executable is blocked through the guard before producing its expected output.
6. Audit JSON is parseable end-to-end.
7. Sprint 2 replay still passes.
8. Sprint 4 replay still passes.
9. Sprint 5 Docker replay still passes.
10. F4 remains explicitly disclosed in the Sprint 6 proof memo.

## Stop Conditions

Stop with a blocker memo instead of forcing integration if:

- The OpenHands runtime image cannot be pulled or run locally.
- The image requires unavailable privileges or startup assumptions for a one-file command probe.
- The guard cannot be run in the runtime image without installing new packages or mutating the runtime image.
- The result would only prove an arbitrary Docker process again rather than the OpenHands runtime image.

## Claims Not Allowed

- No claim of full OpenHands app integration.
- No claim that an OpenHands LLM agent was supervised.
- No claim that F4 is fixed.
- No claim of production-grade sandboxing.
- No claim of full filesystem, network, or data-exfiltration isolation.

