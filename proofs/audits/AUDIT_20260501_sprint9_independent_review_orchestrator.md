# Sprint 9 — Independent Audit Review Summary

Date: 2026-05-01

Source: user-provided consolidated audit notes from Sprint 9 audit agents.

## Consensus

Sprint 9 core proof is supported.

It is review-ready as a guided/prepared-lab prepared-lab demo.

It is not yet honest as a public self-serve "clone and run one command" demo.

## Findings

### High: One-command demo is local-machine shaped

The first Sprint 9 runner and docs were tied to this lab machine:

- hardcoded `/home/blazingradar/agent-exec-guard-lab`;
- local env-file example in docs;
- existing `external/OpenHands-1.6.0` assumption;
- existing Python/OpenHands replay environment assumption.

This does not invalidate Sprint 9 as a guided demo. It does invalidate any claim that a public reviewer can clone the repository on a fresh machine and run one command without setup.

### Medium: Runner cleanup was manual

The Sprint 9 run container was cleaned manually after the run. The runner itself did not enforce post-run container cleanup.

### Medium: README status stale

README stated Sprint 9 was "in progress" while proof memo stated PASS.

### Low: Demo wrapper had no aggregate pass/fail summary

The wrapper recorded individual PASS lines but did not append an aggregate `pass=N fail=0` row like other replay harnesses.

## Verified

- Gate commit precedes final commit.
- Guard source/binary unchanged from Sprint 8.
- YAML compiles to guard JSON with 23 allowed executables.
- Negative YAML compiler tests pass.
- Nested OpenHands/GPT run is `pass=11 fail=0`.
- Current-run trajectory assertion ties denial to the correct run.
- No API key pattern found in Sprint 9 artifacts.
- Boundaries are well stated: not web UI, not production sandbox, not non-`CmdRunAction`, not F4 closure.

## Supported Claim

Sprint 9 packages the Sprint 8 OpenHands guard path into a repeatable guided demo: editable YAML compiles to guard JSON, GPT drives `execute_bash`, the guard allows expected executable identities, blocks copied/renamed `/usr/bin/rm`, and the denial is asserted from current-run trajectory evidence.

## Cleanup Plan

Sprint 9 post-audit cleanup should:

1. remove local hardcoded repo path from the demo runner;
2. remove local hardcoded repo path from the Sprint 8 replay path used by the demo;
3. replace local env-file examples with generic `OPENAI_API_KEY` / `.env.local` instructions;
4. add preflight checks for Docker and pinned OpenHands source;
5. add runner-managed container cleanup;
6. append aggregate pass/fail summary;
7. align README status with the proof state;
8. preserve a post-cleanup run artifact.
