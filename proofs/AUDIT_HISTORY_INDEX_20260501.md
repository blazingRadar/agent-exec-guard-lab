# Audit History Index

Date: 2026-05-01

Purpose: single-file index of the sprint gates, proof memos, command logs, independent audits, and preserved run artifacts currently backed up in the private GitHub repository.

Repo: `https://github.com/blazingRadar/agent-exec-guard-lab`

Verified GitHub visibility at time of writing: `PRIVATE`

Verified pushed head at time of writing:

```text
98125d9cfa265cb8aaf9fdb363f0e97d345a81e7 refs/heads/main
```

## Repository Evidence Shape

The repository intentionally preserves:

- pre-registered sprint gates;
- proof memos;
- command logs;
- independent audit reports;
- failed and passing replay artifacts;
- source and binary hashes;
- run-local Docker/OpenHands metadata;
- known caveats and non-claims.

The proof directory currently contains 109 files and is approximately 28 MB.

## Sprint Chain

| Sprint | Main artifact | Audit / evidence status |
| --- | --- | --- |
| Sprint 1 | `SPRINT1_RAW_RUNTIME_BOUNDARY_20260430.md` | Raw seccomp user-notify mechanism proof; partial pass; Docker/OpenHands not claimed |
| Sprint 2 | `SPRINT2_IDENTITY_HARDENING_20260430.md` | Identity hardening; independent audits A/B preserved |
| Sprint 3 | `SPRINT3_LANDLOCK_UNDERLAY_20260430.md` | Landlock execute underlay; independent Sprint 3 audit preserved |
| Sprint 4 | `SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md` | Audit-integrity hardening; independent audits A/B plus subagent audits preserved |
| Sprint 5 | `SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` | Docker feasibility proof; independent audits and follow-up cleanup preserved |
| Sprint 6 | `SPRINT6_OPENHANDS_RUNTIME_PROOF_20260501.md` | OpenHands runtime one-file proof; gate and command log preserved |
| Sprint 6B | `SPRINT6B_ACTION_SERVER_PROOF_20260501.md` | OpenHands action server proof; independent audits A/B and post-audit cleanup preserved |
| Sprint 7 | `SPRINT7_HEADLESS_AGENT_PROOF_20260501.md` | Headless OpenHands agent-loop proof; independent audits A/B preserved |
| Sprint 8 | `SPRINT8_FRONTIER_MODEL_PROOF_20260501.md` | External OpenAI model proof; cleanup memo preserved |
| Sprint 9 | `SPRINT9_PRODUCTIZED_DEMO_PROOF_20260501.md` | Productized one-command demo with editable YAML policy; run artifacts preserved |

## Gate Memos

- `proofs/SPRINT5_GATE_20260430.md`
- `proofs/SPRINT6_GATE_20260501.md`
- `proofs/SPRINT6B_GATE_20260501.md`
- `proofs/SPRINT7_GATE_20260501.md`
- `proofs/SPRINT8_GATE_20260501.md`
- `proofs/SPRINT9_GATE_20260501.md`

Sprint 9 specifically preserves the process correction from earlier audits: the gate commit precedes implementation/proof commit in git history.

## Independent Audit Reports

- `proofs/AUDIT_20260430_sprint1_independent_review.md`
- `proofs/AUDIT_20260430_sprint2_independent_review_a.md`
- `proofs/AUDIT_20260430_sprint2_independent_review_b.md`
- `proofs/AUDIT_20260430_sprint3_independent_review.md`
- `proofs/AUDIT_20260430_sprint4_independent_review_a.md`
- `proofs/AUDIT_20260430_sprint4_independent_review_b.md`
- `proofs/AUDIT_20260430_sprint4_subagent_hume.md`
- `proofs/AUDIT_20260430_sprint4_subagent_maxwell.md`
- `proofs/AUDIT_20260430_sprint5_followup_review.md`
- `proofs/AUDIT_20260430_sprint5_independent_review_a.md`
- `proofs/AUDIT_20260430_sprint5_independent_review_b.md`
- `proofs/AUDIT_20260430_sprint5_subagent_bohr.md`
- `proofs/AUDIT_20260430_sprint5_subagent_laplace.md`
- `proofs/AUDIT_20260501_sprint6b_independent_review_a.md`
- `proofs/AUDIT_20260501_sprint6b_independent_review_b.md`
- `proofs/AUDIT_20260501_sprint7_independent_review_a.md`
- `proofs/AUDIT_20260501_sprint7_independent_review_b.md`
- `proofs/AUDIT_20260501_sprint8_independent_review_orchestrator.md`

## Preserved Run Directories

- `proofs/sprint2_runs/`
- `proofs/sprint3_scratch/`
- `proofs/sprint4_runs/`
- `proofs/sprint5_runs/`
- `proofs/sprint6_runs/`
- `proofs/sprint6b_runs/`
- `proofs/sprint7_runs/`
- `proofs/sprint8_runs/`
- `proofs/sprint9_runs/`

## Current Strongest Claim

Sprint 9 packages the proven OpenHands guard path into a repeatable CLI demo: an editable YAML policy compiles into the guard's JSON allowlist, the one-command runner launches the pinned OpenHands headless agent path, an external OpenAI model drives `execute_bash`, the guard allows expected executable identities, blocks copied/renamed `/usr/bin/rm`, emits parseable audit JSON, and the denial is asserted from the current-run OpenHands trajectory.

## Current Non-Claims

- Full OpenHands web UI coverage.
- Production-grade sandbox security.
- Complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure.
- fd-stable execution.
- Read/write/network isolation.
- Browser, Jupyter, MCP, `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, or non-`CmdRunAction` coverage.
- Minimal production policy.

## Backup Status

As of this index, all Sprint 1-9 proof artifacts known to the current working tree are committed and pushed to the private GitHub repository. Future audits should update this file when new sprint gates, proof memos, audit reports, or run directories are added.
