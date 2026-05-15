# Publication Manifest

This repository is a public research artifact for a narrow runtime-security question: can an agent command path be governed below the model/tool layer by a Linux execution-boundary guard?

## Included

- C guard implementation for seccomp user-notification executable-identity enforcement.
- Policy examples and a YAML-to-JSON policy compiler.
- Guided OpenHands demo scripts and policy-workflow scripts.
- Sprint gates, proof memos, command logs, independent audits, and preserved run artifacts.
- A static demo page under `demo/` for quick visual review.

## Claim Boundary

The current strongest claim is the Sprint 10 policy-workflow claim in `proofs/memos/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md`: on the prepared lab machine, real guard audit logs from a pinned OpenHands demo can generate reviewable YAML policy, compile to guard JSON, and rerun the guided demo successfully while preserving the copied-`rm` block assertion.

The repository does not claim production sandbox security, complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure, full OpenHands web UI coverage, non-`CmdRunAction` coverage, read/write/network isolation, automatic policy approval, or signed/tamper-proof audit logs.

## Repository Hygiene

- API keys and environment files are not included.
- Current scripts derive the repository root dynamically or accept explicit root/environment variables.
- The preserved proof tree intentionally includes historical command logs and run outputs. Some historical artifacts retain host-local proof paths because they are raw evidence of the run environment.
- Strategy, IP-boundary, and source-tracking notes that were not part of the evidence chain are excluded from the public artifact.
- Copied replay executable payloads are excluded from the tracked public tree; commands, stdout/stderr, policies, hashes, and run metadata remain preserved.

## Verification Surface

The public verification surface is shell syntax checks, Python bytecode compilation, policy compiler checks, JSON parsing, Markdown link checks, public-surface hygiene scans, and a fresh-clone smoke check. Full Docker/OpenHands replay requires the original prepared lab environment and is not treated as a public self-serve test in this repository.
