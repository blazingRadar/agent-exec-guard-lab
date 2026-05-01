# Sprint 5 Proof Cleanup

Date: 2026-05-01
Lab: `/home/blazingradar/agent-exec-guard-lab`
Scope: proof-quality cleanup only. No guard behavior was changed.

## Audit Inputs

The Sprint 5 audit reports are preserved at:

- `proofs/AUDIT_20260430_sprint5_independent_review_a.md`
- `proofs/AUDIT_20260430_sprint5_independent_review_b.md`
- `proofs/AUDIT_20260430_sprint5_subagent_bohr.md`
- `proofs/AUDIT_20260430_sprint5_subagent_laplace.md`

## Findings Addressed

| Audit item | Cleanup action |
|---|---|
| Default Docker seccomp claim needed positive retained metadata | Harness now records `docker inspect` and `/proc/self/status` from a created container. Latest run retains `HostConfig.SecurityOpt=None` and `Seccomp: 2`. |
| Raw OpenHands pin provenance not preserved | Raw `gh` and Docker manifest outputs were saved under `proofs/sprint5_provenance/`. |
| Extra failure-only validations should count as passes | Harness now records explicit pass rows for `allowed_python_decision` and `blocked_renamed_rm_reason`. |
| Final run `sha256s.txt` omitted replay script hash | Harness now includes `scripts/integration/replay_sprint5_docker_guard.sh` in `sha256s.txt`. |
| Carry-forward register was too short | Sprint 5 memo now carries F1-F8, A1-A4, B5-B6, F4, OpenHands runtime, and production-sandbox status. |
| Pre-registration by git timeline | Not retroactively fixable for Sprint 5. Sprint 6 must commit and push its gate before implementation starts. |

## Latest Cleanup Replay

```text
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T002321Z
pass=11 fail=0
```

## Claim After Cleanup

The Sprint 5A claim is unchanged but better evidenced:

> The guard ran inside a `python:3.12-slim` Docker container using the harness's normal Docker run path with `HostConfig.SecurityOpt=None` and in-container `Seccomp: 2`, allowed approved Python execution, blocked a copied/renamed `/bin/rm` before output, demoted forged child JSON to `child_stderr`, preserved Sprint 2 and Sprint 4 replay claims, and left F4 explicitly disclosed.

## Sprint 6 Discipline Requirement

Sprint 6 must start with a standalone gate commit:

```text
1. Write `proofs/SPRINT6_GATE_*.md`.
2. Include the full carry-forward register.
3. Commit and push only the gate.
4. Begin implementation after the gate commit is on `origin/main`.
```
