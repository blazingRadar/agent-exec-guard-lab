# Sprint 5 — Subagent Audit Review (Bohr)

Date: 2026-04-30
Auditor: Bohr (`019de0da-b881-7273-9220-eaeab130d7a3`)
Posture: read-only Docker/container runtime correctness audit.
Scope: Sprint 5 Docker integration proof for `/home/blazingradar/agent-exec-guard-lab`.

## Findings

No blocking findings found.

Low residual evidence gap: the proof supports "not `seccomp=unconfined`" from the replay harness command, because `docker run` has no `--security-opt seccomp=unconfined` or equivalent option at `scripts/integration/replay_sprint5_docker_guard.sh:66`. It does not retain positive container runtime metadata such as `docker inspect HostConfig.SecurityOpt` or `/proc/self/status Seccomp:` from inside the container. I would still accept the claim as stated for this sprint, but the next proof should record that metadata.

## Supported Claim

Sprint 5 supports this bounded claim: the guard ran inside a `python:3.12-slim` Docker container, using the harness's default `docker run` invocation rather than `seccomp=unconfined`; the final replay passed `6/0`; an allowed Python exec was permitted; a copied/renamed `/bin/rm` was blocked before producing `rm --version`; forged child JSON was emitted as `child_stderr`; Sprint 2 and Sprint 4 regression gates remained green; and F4 remains explicitly disclosed/deferred.

Evidence:

- Final Sprint 5 replay: `pass=6 fail=0` at `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/replay_summary.txt:10`, matching the memo at `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:52`.
- Docker command path: guard invoked inside `docker run` at `scripts/integration/replay_sprint5_docker_guard.sh:66`, with no unconfined seccomp option.
- Renamed `/bin/rm`: fixture copies `/bin/rm` then executes it through the guard at `scripts/integration/replay_sprint5_docker_guard.sh:107`; artifact shows `decision":"BLOCK"` and `reason":"blocked_executable_identity"` at `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/blocked_renamed_rm/stderr.txt:1`, with replay summary recording "renamed rm did not execute" at `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/replay_summary.txt:7`.
- Forged JSON: test writes fake `exec_decision` JSON at `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/forge_stderr.py:2`, and artifact captures it as `child_stderr` at `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/stderr_forgery_contained/stderr.txt:2`.
- Sprint 2 preserved: `pass=12 fail=0` at `proofs/sprint2_runs/sprint2-20260430T235805Z/replay_summary.txt:15`.
- Sprint 4 preserved: `pass=22 fail=0` at `proofs/sprint4_runs/sprint4-20260430T235809Z/replay_summary.txt:25`.
- F4 deferred/disclosed: explicit carry-forward at `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:11`, and "No claim that F4 is fixed" at `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:95`.

The proof also correctly avoids overclaiming OpenHands integration: it says the pinned runtime was identified but not pulled/exercised at `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:12` and `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md:93`.
