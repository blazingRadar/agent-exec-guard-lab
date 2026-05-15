# Audit History Index

Date: 2026-05-01

Purpose: single-file index of the sprint gates, proof memos, command logs, independent audits, and preserved run artifacts in this repository.

Repo: `https://github.com/blazingRadar/agent-exec-guard-lab`

Verified GitHub visibility at time of writing: historical value from original closeout. Current visibility should be checked with `gh repo view blazingRadar/agent-exec-guard-lab --json visibility`.

Latest pushed head should be verified with `git ls-remote origin refs/heads/main` after each update. Current Sprint 10 work begins at:

```text
6d91c21 Pre-register Sprint 10 policy workflow gate
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

The proof directory currently contains 4120 files and is approximately 29 MB.

## Sprint Chain

| Sprint | Main artifact | Audit / evidence status |
| --- | --- | --- |
| Sprint 1 | `proofs/memos/SPRINT1_RAW_RUNTIME_BOUNDARY_20260430.md` | Raw seccomp user-notify mechanism proof; partial pass; Docker/OpenHands not claimed |
| Sprint 2 | `proofs/memos/SPRINT2_IDENTITY_HARDENING_20260430.md` | Identity hardening; independent audits A/B preserved |
| Sprint 3 | `proofs/memos/SPRINT3_LANDLOCK_UNDERLAY_20260430.md` | Landlock execute underlay; independent Sprint 3 audit preserved |
| Sprint 4 | `proofs/memos/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md` | Audit-integrity hardening; independent audits A/B plus subagent audits preserved |
| Sprint 5 | `proofs/memos/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` | Docker feasibility proof; independent audits and follow-up cleanup preserved |
| Sprint 6 | `proofs/memos/SPRINT6_OPENHANDS_RUNTIME_PROOF_20260501.md` | OpenHands runtime one-file proof; gate and command log preserved |
| Sprint 6B | `proofs/memos/SPRINT6B_ACTION_SERVER_PROOF_20260501.md` | OpenHands action server proof; independent audits A/B and post-audit cleanup preserved |
| Sprint 7 | `proofs/memos/SPRINT7_HEADLESS_AGENT_PROOF_20260501.md` | Headless OpenHands agent-loop proof; independent audits A/B preserved |
| Sprint 8 | `proofs/memos/SPRINT8_FRONTIER_MODEL_PROOF_20260501.md` | External OpenAI model proof; cleanup memo preserved |
| Sprint 9 | `proofs/memos/SPRINT9_PRODUCTIZED_DEMO_PROOF_20260501.md` | Guided one-command demo with editable YAML policy; post-audit cleanup and run artifacts preserved |
| Sprint 10 | `proofs/memos/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md` | Observe/generate/review/enforce policy workflow; independent audits and post-audit cleanup preserved |

## Gate Memos

- `proofs/gates/SPRINT5_GATE_20260430.md`
- `proofs/gates/SPRINT6_GATE_20260501.md`
- `proofs/gates/SPRINT6B_GATE_20260501.md`
- `proofs/gates/SPRINT7_GATE_20260501.md`
- `proofs/gates/SPRINT8_GATE_20260501.md`
- `proofs/gates/SPRINT9_GATE_20260501.md`
- `proofs/gates/SPRINT10_GATE_20260501.md`

Sprint 9 specifically preserves the process correction from earlier audits: the gate commit precedes implementation/proof commit in git history.

## Independent Audit Reports

- `proofs/audits/AUDIT_20260430_sprint1_independent_review.md`
- `proofs/audits/AUDIT_20260430_sprint2_independent_review_a.md`
- `proofs/audits/AUDIT_20260430_sprint2_independent_review_b.md`
- `proofs/audits/AUDIT_20260430_sprint3_independent_review.md`
- `proofs/audits/AUDIT_20260430_sprint4_independent_review_a.md`
- `proofs/audits/AUDIT_20260430_sprint4_independent_review_b.md`
- `proofs/audits/AUDIT_20260430_sprint4_subagent_hume.md`
- `proofs/audits/AUDIT_20260430_sprint4_subagent_maxwell.md`
- `proofs/audits/AUDIT_20260430_sprint5_followup_review.md`
- `proofs/audits/AUDIT_20260430_sprint5_independent_review_a.md`
- `proofs/audits/AUDIT_20260430_sprint5_independent_review_b.md`
- `proofs/audits/AUDIT_20260430_sprint5_subagent_bohr.md`
- `proofs/audits/AUDIT_20260430_sprint5_subagent_laplace.md`
- `proofs/audits/AUDIT_20260501_sprint6b_independent_review_a.md`
- `proofs/audits/AUDIT_20260501_sprint6b_independent_review_b.md`
- `proofs/audits/AUDIT_20260501_sprint7_independent_review_a.md`
- `proofs/audits/AUDIT_20260501_sprint7_independent_review_b.md`
- `proofs/audits/AUDIT_20260501_sprint8_independent_review_orchestrator.md`
- `proofs/audits/AUDIT_20260501_sprint9_independent_review_orchestrator.md`
- `proofs/audits/AUDIT_20260501_sprint9_independent_review_orchestrator_pass2.md`
- `proofs/audits/AUDIT_20260501_sprint10_independent_review_a.md`
- `proofs/audits/AUDIT_20260501_sprint10_independent_review_b.md`
- `proofs/audits/AUDIT_20260501_sprint10_followup_review.md`

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
- `proofs/sprint10_runs/`

## Current Strongest Claim

Sprint 10 adds an observe/generate/review/enforce workflow: real guard audit logs from the OpenHands demo are converted into reviewable YAML policy, observed BLOCK records are preserved separately, any realpath seen in both ALLOW and BLOCK is excluded from the generated allowlist, that YAML compiles to guard JSON, and the guided OpenHands demo reruns successfully under the generated policy while preserving the copied-`rm` block assertion.

## Current Non-Claims

- Full OpenHands web UI coverage.
- Production-grade sandbox security.
- Complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure.
- fd-stable execution.
- Read/write/network isolation.
- Browser, Jupyter, MCP, `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, or non-`CmdRunAction` coverage.
- Minimal production policy.
- Public self-serve clone-and-run packaging.
- Recorded outreach video/asciinema.
- Automatic policy approval without human review.
- Signed or tamper-proof audit logs.

## Backup Status

As of this index, all Sprint 1-10 proof artifacts known to the current working tree are included in the Sprint 10 post-audit cleanup set. The git commit and push record are the backup evidence. Future audits should update this file when new sprint gates, proof memos, audit reports, or run directories are added.
