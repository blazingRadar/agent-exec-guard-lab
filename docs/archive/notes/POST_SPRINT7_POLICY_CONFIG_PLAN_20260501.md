# Post-Sprint 7 Policy Config Plan

Date: 2026-05-01

Status: deferred until after Sprint 7 full OpenHands environment proof

## Why This Matters

The current guard is useful as an execution-universe boundary, but it is not yet ergonomic for real users. OpenHands and similar agent runtimes can produce command variance across tasks, models, environments, and retries. A hardcoded allowlist is acceptable for lab proof, but a usable tool needs a policy workflow that lets a user discover, review, and enforce the executable footprint for their own environment.

## Product Direction

Add a user-facing policy config, preferably YAML, with explicit modes:

```yaml
profile: openhands-runtime-demo
mode: enforce

allowed_executables:
  - /usr/bin/bash
  - /usr/bin/sh
  - /usr/bin/cat
  - /usr/bin/git
  - /usr/bin/cp
  - /usr/bin/chmod

blocked_executables:
  - /usr/bin/rm
  - /usr/bin/curl
  - /usr/bin/wget

audit:
  output: ./agent-exec-guard.audit.jsonl
  include_argv: true
  include_sha256: true

on_unknown_executable: block
```

## Workflow To Build Later

1. Observe mode

Run OpenHands or another agent runtime normally under the guard, but do not block unknown executables. Record every requested executable identity, argv sample, cwd, hash, and decision operator.

2. Generate policy

Convert observed executable identities into a proposed YAML allowlist. Mark risky or surprising executables for review rather than automatically approving them.

3. Human review

The operator edits and approves the policy. This is where the project becomes practical: the user can tune the execution universe to their actual agent workflow instead of inheriting a lab policy.

4. Enforce mode

Rerun the same workflow with `on_unknown_executable: block`. Unknown or off-policy executable identities fail closed and emit audit records.

## Claim Boundary

This does not make the guard a complete sandbox. It still governs process execution identity, not all shell builtins, file writes, network operations, or data exfiltration. The right public claim is:

> Drop this into an agent runtime, observe its executable footprint, review the generated policy, then enforce a fail-closed execution boundary with audit records.

## When To Revisit

Revisit after Sprint 7 proves the full OpenHands app / LLM-agent workflow. Do not let this productization work delay the next integration proof.
