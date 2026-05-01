# Sprint 6B Post-Audit Cleanup

Date: 2026-05-01

Status: PASS

## Why This Cleanup Happened

Sprint 6B passed independent audit as a real OpenHands action-server command-path proof. The auditors still found cleanup work worth doing before Sprint 7:

- preserve the independent audit memos and reproduced replay runs;
- add missing Sprint 6B metadata checks for in-container seccomp and guarded-child `NoNewPrivs`;
- tighten the claim boundary around pinned source plus pinned runtime image;
- carry forward non-`CmdRunAction` action paths, bind-mounted source topology, and F4 as explicit Sprint 7+ items.

## Changes Made

### 1. Audit Memos And Reproduced Runs Preserved

The independent Sprint 6B audit memos were kept under:

- `proofs/AUDIT_20260501_sprint6b_independent_review_a.md`
- `proofs/AUDIT_20260501_sprint6b_independent_review_b.md`

Auditor reproduced run directories are also preserved under the matching `proofs/sprint*_runs/` folders.

### 2. Sprint 6B Harness Metadata Checks Added

`scripts/integration/replay_sprint6b_action_server.sh` now records:

- Docker `HostConfig.SecurityOpt=None`;
- in-container `/proc/self/status` reporting `Seccomp: 2`;
- guarded `/execute_action` child `cat /proc/self/status` reporting `NoNewPrivs: 1` and `Seccomp: 2`.

This closes the partial acceptance-criterion gap identified by the Sprint 6B audit.

### 3. Stopped Exploratory Containers Removed

Two stopped exploratory Docker containers from earlier manual Sprint 6B probing were removed:

- `aeg-s6b-action-server`
- `aeg-s6b-action-server-src`

The final replay harness already cleans up containers it owns.

## Cleanup Replay

Command:

```bash
./scripts/integration/replay_sprint6b_action_server.sh
```

Final cleanup run:

```text
proofs/sprint6b_runs/sprint6b-action-server-20260501T011210Z
```

Result:

```text
PASS source_commit c5e0de8ecd85cef10e7808d57e9f939f3770ab9d
PASS image_identity recorded
PASS docker_run container started
PASS docker_inspect recorded
PASS docker_securityopt_default HostConfig.SecurityOpt=None
PASS docker_proc_status_seccomp container reports Seccomp:2
PASS alive_probe server returned /alive
PASS action_allowed_cat HTTP action returned
PASS action_allowed_cat_result workspace file read via /execute_action
PASS action_guarded_proc_status HTTP action returned
PASS action_guarded_proc_status_result guarded action child reports NoNewPrivs:1 and Seccomp:2
PASS action_block_renamed_rm HTTP action returned
PASS action_block_renamed_rm_result renamed rm blocked via /execute_action
PASS container_logs_json guard audit lines parse
PASS guard_log_blocked_python3 guard logged copied rm block
pass=15 fail=0
```

An earlier cleanup run at `proofs/sprint6b_runs/sprint6b-action-server-20260501T011132Z` is preserved as a failed harness-expectation run. The metadata was present, but the check was too strict about whitespace in `/proc/self/status`. The follow-up pass changed the check to parse fields instead of assuming tab formatting.

## Hashes After Cleanup

```text
07df7647f522ba003982f7fef0b31002f01f2b1204d9950fb4e7042c1f90df19  scripts/integration/replay_sprint6b_action_server.sh
dd30a713eda6af691c6a58879f8710a5fe0e3c102f7308d35fc37936d2a12134  proofs/SPRINT6B_GATE_20260501.md
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
ccfa471b1e2576913f0751138ac41d35a65aeefd746f3b6734ff2bac0d942393  policy/integration/openhands_action_server.allow.json
```

The guard source and binary did not change in this cleanup. The change is harness/proof metadata only.

## Sprint 7 Carry-Forward

Sprint 7 should start from this clean boundary:

- Sprint 6B proves pinned OpenHands source plus pinned runtime image action-server `CmdRunAction` supervision.
- The `/execute_action` request is harness-issued, not LLM-agent-issued.
- Non-`CmdRunAction` paths remain out of scope: `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, `BrowseURLAction`, and non-`/execute_action` endpoints such as upload/list/update paths.
- The current proof uses a bind-mounted pinned source tree, not a production-shaped image with the guard copied into it.
- F4 remains disclosed and deferred.
- Production-grade sandboxing is still not claimed.

## Claim After Cleanup

The guard can wrap the pinned OpenHands 1.6.0 action-execution server command path, supervise real `/execute_action` `CmdRunAction` requests through the runtime shell, allow an approved workspace file read, prove guarded action children run under `NoNewPrivs:1` and `Seccomp:2`, block a copied and renamed `/usr/bin/rm`, and preserve prior regression gates under Docker default security settings.
