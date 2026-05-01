# Sprint 9 Gate: Productized CLI Demo and Editable Policy Config

Date: 2026-05-01

Status: PRE-REGISTERED BEFORE IMPLEMENTATION

## Goal

Sprint 9 turns the proven lab path into a repeatable demo artifact.

Target claim:

> A reviewer can run one command to execute the pinned OpenHands headless agent demo with the guard enabled, using an editable YAML policy source that is compiled to the guard's JSON policy format before execution.

This is not a new kernel/security-mechanism sprint. The guard source and binary should remain unchanged unless a replay catches a blocking bug. The work is productization: configuration, packaging, docs, and proof hygiene.

## Prior State

Sprint 8 proved:

- pinned OpenHands source tag `1.6.0`, commit `c5e0de8ecd85cef10e7808d57e9f939f3770ab9d`;
- pinned runtime image `ghcr.io/openhands/runtime:1.6.0-nikolaik`;
- external OpenAI `gpt-5.2` in the loop;
- real `CodeActAgent` `execute_bash` actions;
- guarded runtime action-server command path;
- allowed `cat input.txt`;
- blocked copied `/usr/bin/rm` renamed to `./python3`;
- denial surfaced through OpenHands trajectory;
- structured current-run trajectory assertions after the Sprint 7/8 cleanup.

Sprint 8 did not prove:

- full OpenHands web UI;
- production-grade sandboxing;
- non-`CmdRunAction` coverage;
- F4 closure;
- broad model-general behavior.

## Acceptance Criteria

Sprint 9 passes only if all are true:

1. Gate commit precedes implementation/proof commit in git history.
2. Guard source and binary remain unchanged from Sprint 8, unless a blocking bug is found and disclosed.
3. A human-editable YAML policy file exists for the OpenHands action-server demo.
4. A compiler/validator converts that YAML policy into the existing JSON policy schema consumed by the guard.
5. The compiler fails closed on malformed YAML, missing executable entries, non-absolute paths, or missing executable files.
6. A one-command demo runner exists and writes all artifacts to a fresh run directory.
7. The demo runner performs the YAML compile step before launching the OpenHands run.
8. The demo runner preserves provider/model metadata without secrets.
9. The demo runner preserves structured trajectory assertions, guard logs, Docker inspect metadata, and replay summary.
10. The demo passes at least once with an external model if an API key is available.
11. The demo has a no-secret mode or clear blocker if no API key is available.
12. Documentation states exact claims and non-claims, including F4, non-`CmdRunAction`, and non-production status.
13. `/tmp` is not used for retained artifacts.

## Preferred Deliverables

- `policy/examples/openhands_action_server.yaml`
- `scripts/policy/compile_policy.py`
- `scripts/demo/run_openhands_guard_demo.sh`
- `README.md` or `docs/DEMO.md` update with exact run command
- `proofs/SPRINT9_PRODUCTIZED_DEMO_PROOF_20260501.md`
- `proofs/SPRINT9_COMMAND_LOG_20260501.md`

## Stop Conditions

Stop and report a bounded blocker if:

- the YAML policy cannot compile to the existing guard JSON schema without changing guard code;
- the one-command demo cannot run without writing secrets into artifacts;
- OpenHands runtime behavior changes in a way that breaks the established Sprint 8 path;
- productization requires broad architectural changes.

## Carry-Forward Open Items

| Item | Status entering Sprint 9 |
| --- | --- |
| F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred and disclosed |
| Non-`CmdRunAction` paths | Out of scope unless specifically tested |
| `FileReadAction` / `FileWriteAction` | Not covered by exec guard by design |
| `IPythonRunCellAction` / `BrowseURLAction` | Not covered unless tested |
| Full OpenHands web UI | Not targeted in Sprint 9 |
| Production-shaped image | Not targeted in Sprint 9 |
| YAML policy workflow | Target of Sprint 9 |
| One-command demo | Target of Sprint 9 |
| Production-grade sandbox claim | Not allowed |

## Claim If Successful

Use this shape only if supported by artifacts:

> Sprint 9 packages the proven OpenHands guard path into a repeatable CLI demo: an editable YAML policy compiles into the guard's JSON allowlist, the one-command runner launches the pinned OpenHands headless agent path, an external model drives `execute_bash`, the guard allows expected executable identities, blocks copied/renamed `/usr/bin/rm`, emits parseable audit JSON, and the denial is asserted from the current-run OpenHands trajectory.

## Claim If Not Successful

If the sprint hits a blocker:

> Sprint 9 did not yet produce the one-command productized demo. The blocked reason is [specific blocker]. Sprint 8 remains the supported external frontier-model OpenHands proof.
