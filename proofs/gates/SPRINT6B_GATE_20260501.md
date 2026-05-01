# Sprint 6B Gate: OpenHands Runtime Command-Path Probe

Date: 2026-05-01
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: pre-registered gate. This file must be committed and pushed before Sprint 6B implementation starts.

## Goal

Move from Sprint 6A's "guard works inside the pinned OpenHands runtime image" to the narrowest honest proof of an OpenHands runtime command path.

Sprint 6B should inspect the pinned runtime image and local OpenHands artifacts, identify the command-entry mechanism available inside the runtime, and prove whether the guard can supervise that path.

## Target

```text
runtime image: ghcr.io/openhands/runtime:1.6.0-nikolaik
observed manifest-list digest: sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60
observed amd64 child digest: sha256:4959cef8059841fa5bf05fb1368d9ce5735d0ba94b2a3ceee335285e26529452
```

## Carry-Forward Open Items

| ID | Item | Sprint 6B status before work |
|---|---|---|
| F1 | Audit log forgery via shared fd 2 | Closed in Sprint 4; must not regress. |
| F2 | Supervisor killable by child via SIGTERM without final audit | Closed best-effort in Sprint 4; SIGKILL remains uncatchable. |
| F3 | Policy parser fail-open on malformed `allowed_executables` | Closed in Sprint 4; must not regress. |
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred. Sprint 6B does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. Must be disclosed. |
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
| Sprint 6A | OpenHands runtime image one-file proof | Closed; Sprint 6B must move closer to command-entry semantics. |
| Production sandboxing | Complete production-grade sandbox claim | Not allowed. |

## Acceptance Criteria

Sprint 6B passes only if all of these are true:

1. The runtime image command-entry surface is inspected and recorded.
2. The proof identifies one concrete command-entry mechanism inside the runtime image, or stops with a blocker memo if none is available without the full OpenHands app.
3. The guard supervises that concrete command-entry mechanism, not merely an unrelated arbitrary command, if such a mechanism is available.
4. At least one allowed command operates on a one-file workspace through that mechanism.
5. A copied/renamed non-policy executable is blocked through the guard before producing expected output.
6. Audit JSON is parseable end-to-end.
7. Docker metadata is preserved:
   - `HostConfig.SecurityOpt`
   - in-container `/proc/self/status` `Seccomp:`
   - guarded child `NoNewPrivs:`
8. Sprint 2 replay still passes.
9. Sprint 4 replay still passes.
10. Sprint 5 replay still passes.
11. Sprint 6A runtime replay still passes.
12. F4 remains explicitly disclosed in the Sprint 6B proof memo.

## Stop Conditions

Stop with a blocker memo instead of forcing a fake integration if:

- The runtime image has no command-entry surface independent of the full OpenHands app.
- The command path requires a live OpenHands server, LLM session, or app container not in scope for this sprint.
- The result would only repeat Sprint 6A's arbitrary command proof.
- The guard can only be inserted by modifying OpenHands internals in a way that is not auditable in one short sprint.

## Claims Not Allowed

- No claim of full OpenHands app integration unless the full app command path is actually exercised.
- No claim that an LLM agent was supervised unless a real agent action is executed and captured.
- No claim that F4 is fixed.
- No claim of production-grade sandboxing.
- No claim of complete filesystem, network, or data-exfiltration isolation.

