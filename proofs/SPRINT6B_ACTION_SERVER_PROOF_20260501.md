# Sprint 6B Action Server Proof

Date: 2026-05-01

Gate: `proofs/SPRINT6B_GATE_20260501.md`

Gate commit: `c4392ae Pre-register Sprint 6B OpenHands command path gate`

Result: PASS

Post-audit cleanup: `proofs/SPRINT6B_POST_AUDIT_CLEANUP_20260501.md` adds the missing in-container `Seccomp:2` and guarded-child `NoNewPrivs:1` metadata checks requested by Sprint 6B auditors. The guard source and binary did not change.

Final run root:

`proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z`

## Carry-Forward Open Items

| Item | Current status |
| --- | --- |
| F1 audit log forgery via shared fd 2 | Closed in Sprint 4; preserved in Sprint 5 and Sprint 6 regressions |
| F2 supervisor killable by child via SIGTERM | Best-effort signal audit closed in Sprint 4; SIGKILL remains uncatchable by design |
| F3 policy parser fail-open | Closed in Sprint 4 |
| F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred and disclosed; not fixed by Sprint 6B |
| F5 `/proc/self/exe` supervisor namespace resolution | Closed in Sprint 4 |
| F6 external `sha256sum` helper | Closed in Sprint 4 with AF_ALG |
| F7 argv truncation metadata | Closed in Sprint 4 |
| F8 policy_id escape parsing | Closed in Sprint 4 |
| A1 JSON parser depth limit | Closed in Sprint 4 sweep |
| A2 argv count cap marker | Closed in Sprint 4 sweep |
| A3 child stderr NUL handling | Closed in Sprint 4 sweep |
| A4 SIGKILL disclosure | Documented; SIGKILL cannot be caught |
| B5 signal handler async-signal-safe sweep | Closed in Sprint 4 sweep |
| B6 Unicode escape handling | Closed for BMP escapes; surrogate pairs remain unsupported and fail closed |
| Sprint 6A OpenHands runtime one-file proof | Closed in Sprint 6A |
| Full OpenHands app / LLM-agent proof | Not claimed in Sprint 6B |
| Production-grade sandbox claim | Not claimed |

## What Was Tested

Sprint 6B tested the pinned OpenHands runtime command execution server, not just an arbitrary process inside the image.

Pinned OpenHands source:

- Tag: `1.6.0`
- Commit: `c5e0de8ecd85cef10e7808d57e9f939f3770ab9d`
- Local inspection clone: `external/OpenHands-1.6.0` (ignored by git; commit recorded in proofs)

Pinned runtime image:

- `ghcr.io/openhands/runtime:1.6.0-nikolaik`

The inspected command path is:

1. `openhands/runtime/action_execution_server.py`
2. `/execute_action` receives a serialized `CmdRunAction`
3. `ActionExecutor.run()` dispatches the action
4. `BashSession.execute()` runs the command in the runtime shell

The harness starts that action server under the guard:

```text
/lab/bin/usernotify_exec_guard
  --policy /lab/policy/integration/openhands_action_server.allow.json
  /openhands/micromamba/bin/micromamba run -n openhands
  poetry run python -u -m openhands.runtime.action_execution_server
  30000 --working-dir <workspace> --username daemon --user-id 1 --no-enable-browser
```

The OpenHands source is mounted read-only at `/openhands/code`, and `PYTHONPATH=/openhands/code` is set. This is necessary because the runtime image contains the OpenHands runtime environment and dependencies but not the importable OpenHands source tree by itself.

## Final Replay

Final command:

```bash
./scripts/integration/replay_sprint6b_action_server.sh
```

Final result:

```text
PASS source_commit c5e0de8ecd85cef10e7808d57e9f939f3770ab9d
PASS image_identity recorded
PASS docker_run container started
PASS docker_inspect recorded
PASS docker_securityopt_default HostConfig.SecurityOpt=None
PASS alive_probe server returned /alive
PASS action_allowed_cat HTTP action returned
PASS action_allowed_cat_result workspace file read via /execute_action
PASS action_block_renamed_rm HTTP action returned
PASS action_block_renamed_rm_result renamed rm blocked via /execute_action
PASS container_logs_json guard audit lines parse
PASS guard_log_blocked_python3 guard logged copied rm block
pass=12 fail=0
```

## Allowed Action Evidence

The allowed `/execute_action` request ran:

```bash
cat input.txt
```

The response recorded:

```text
success=true
exit_code=0
content=sprint6b-action-server-file
```

This proves the guarded OpenHands action server could execute an approved workspace file read through the real HTTP action path.

## Blocked Action Evidence

The blocked `/execute_action` request ran:

```bash
cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version
```

The response recorded:

```text
success=false
exit_code=126
content=bash: ./python3: Operation not permitted
```

The guard audit stream also recorded a block for the copied executable path:

```text
raw_exe="./python3"
reason="blocked_executable_identity"
```

This preserves the Sprint 2 identity property inside the OpenHands action server path: a copied `/usr/bin/rm` renamed to an allowed basename did not execute.

## Regression Gates

After the Sprint 6B final pass, the earlier gates were replayed:

| Gate | Run root | Result |
| --- | --- | --- |
| Sprint 2 identity replay | `proofs/sprint2_runs/sprint2-20260501T005021Z` | pass=12 fail=0 |
| Sprint 4 audit integrity replay | `proofs/sprint4_runs/sprint4-20260501T005022Z` | pass=22 fail=0 |
| Sprint 5 Docker guard replay | `proofs/sprint5_runs/sprint5-docker-20260501T005022Z` | pass=11 fail=0 |
| Sprint 6A OpenHands runtime replay | `proofs/sprint6_runs/sprint6-openhands-runtime-20260501T005024Z` | pass=13 fail=0 |

## Hashes

```text
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
ccfa471b1e2576913f0751138ac41d35a65aeefd746f3b6734ff2bac0d942393  policy/integration/openhands_action_server.allow.json
91d26f02acdbb769b2050eabe597fa128346bf353f52c4f1428459f69e498850  scripts/integration/replay_sprint6b_action_server.sh
dd30a713eda6af691c6a58879f8710a5fe0e3c102f7308d35fc37936d2a12134  proofs/SPRINT6B_GATE_20260501.md
```

## Claim Now Allowed

A local seccomp user-notify plus Landlock execution guard can wrap the pinned OpenHands `action_execution_server.py` runtime path, supervise real `/execute_action` `CmdRunAction` commands through `BashSession`, allow an approved workspace file read, block a copied and renamed `/usr/bin/rm` before output, and preserve parseable guard audit JSON under Docker default seccomp.

## Claims Still Not Allowed

- Full OpenHands web app integration.
- A claim that an LLM autonomously generated the blocked action.
- A claim that F4 is fixed.
- A production-grade sandbox claim.
- Complete filesystem, network, or data-exfiltration isolation.
- A minimal or universal policy for all OpenHands workflows.
- A claim that the mounted source-tree shape exactly matches every deployed OpenHands runtime configuration.

## Notes

Earlier exploratory runs are preserved under `proofs/sprint6b_runs/`. They record the path to the final harness:

- the runtime image did not import `openhands` without mounting source;
- system Python lacked the needed runtime dependencies, so the harness uses the image's micromamba/poetry environment;
- `root` and a new `guarduser` had startup issues in this direct action-server invocation, so the final harness uses existing user `daemon` for server startup while action responses report the OpenHands shell username as `root`;
- policy additions were made for normal action-server startup helpers, but `/usr/bin/rm` itself remains outside policy.

The Sprint 6B proof is therefore an action-server command-path integration proof. It is stronger than Sprint 6A and still narrower than a full OpenHands app or autonomous-agent proof.
