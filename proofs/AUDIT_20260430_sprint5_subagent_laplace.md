# Sprint 5 — Subagent Audit Review (Laplace)

Date: 2026-04-30
Auditor: Laplace (`019de0da-b8b3-7362-8b53-cad2a1074776`)
Posture: read-only proof quality, CTO-readiness, and integration-claim discipline audit.
Scope: `proofs/SPRINT5_GATE_20260430.md`, `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`, `proofs/SPRINT5_COMMAND_LOG_20260430.md`, `scripts/integration/replay_sprint5_docker_guard.sh`, and recorded run artifacts.

## Findings

1. Medium: OpenHands 1.6.0 pin is summarized, but raw provenance is not retained.

   `proofs/SPRINT5_COMMAND_LOG_20260430.md:12` lists the GitHub and Docker manifest commands, and lines 26-29 record the app/runtime digests. `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:34` repeats those facts. I found no retained manifest/`gh api` output artifact under `proofs/`, so a reviewer can verify the recorded pin only by rerunning external queries, not from preserved evidence.

2. Medium: Docker default seccomp evidence is inferential, not directly recorded.

   The claim is stated at `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:22`. The harness command at `scripts/integration/replay_sprint5_docker_guard.sh:66` uses plain `docker run --rm ...` and does not pass `--security-opt seccomp=unconfined`, which supports "default profile by omission." But there is no recorded `docker inspect`/`SecurityOpt`/seccomp status artifact proving the container actually ran under Docker's default seccomp profile.

3. Low: Sprint 5 pass count is accurate for the recorded summary, but the harness has failure-only checks that are not counted as passes.

   The published `pass=6 fail=0` at `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:52` matches the final run summary at `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/replay_summary.txt:4`. However, `scripts/integration/replay_sprint5_docker_guard.sh:105` and line 117 perform `allowed_python_decision` and `blocked_renamed_rm_reason` checks that only add failures, not passes. The artifacts do show the expected ALLOW and BLOCK reasons, but the summary under-represents what was actually checked.

## Verified Evidence

Sprint 5 final run: `pass=6 fail=0`, run root `proofs/sprint5_runs/sprint5-docker-20260501T000055Z`.

The core artifacts support the behavioral claims:

- Allowed Python ran with exit 0 and ALLOW audit: `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/allowed_python/stderr.txt:1`.
- Copied/renamed `rm` was blocked with exit 126 and no `rm --version` output: `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/blocked_renamed_rm/stderr.txt:1`.
- Forged JSON was demoted to `child_stderr`: `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/stderr_forgery_contained/stderr.txt:2`.

Regression gates match the memo: Sprint 2 `pass=12 fail=0`, Sprint 4 `pass=22 fail=0`.

Hash checks match for source, binary, policy, replay script, and gate doc. The final run's `sha256s.txt` omits the replay script hash, but `proofs/SPRINT5_COMMAND_LOG_20260430.md:67` records it correctly.

## CTO-Readiness Judgment

CTO-ready as a Sprint 5A Docker feasibility proof: the guard runs inside a Docker container, allows an approved executable, blocks a copied non-policy executable, preserves audit-forgery containment, and keeps Sprint 2/4 regressions green.

Not CTO-ready as OpenHands integration proof or production sandbox readiness. The docs are disciplined on that point: `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:93` explicitly disclaims OpenHands integration/runtime exercise, F4 closure, production sandboxing, and full isolation.
