# Agent Exec Guard Lab

Private lab for validating a runtime execution guard for AI coding agents before any public demo or repo is shipped.

## Purpose

Build tangible local proof that an OpenHands-style coding agent running in a Docker sandbox can be constrained by a stricter runtime execution policy than Docker's default compatibility profile.

The current artifact is a private, audit-first demo:

- seccomp user-notify execution guard
- Landlock execute underlay
- editable YAML policy compiled to the guard JSON schema
- observed audit logs converted into reviewable YAML policy
- one-command OpenHands headless-agent demo runner
- preserved replay artifacts and audit memos

The deeper governance system remains private.

## Current Status

- Lab initialized: 2026-04-30
- Implementation status: Sprint 10 observe/generate/review/enforce workflow passed
- Public demo status: private audit before any public repo/demo
- Primary target: pinned OpenHands 1.6.0 headless `CodeActAgent` command path
- Proof standard: reproduce locally before publishing anything

## Quick Demo

With Docker available, the pinned OpenHands source already present at `external/OpenHands-1.6.0`, and an OpenAI API key in the environment:

```bash
export OPENAI_API_KEY=...
./scripts/demo/run_openhands_guard_demo.sh
```

The runner compiles `policy/examples/openhands_action_server.yaml` into a fresh run-local JSON policy, launches the pinned OpenHands headless agent proof, and writes artifacts under `proofs/sprint9_runs/`.

This is a guided private demo path, not yet a public self-serve clone-and-run package.

See [docs/DEMO.md](docs/DEMO.md) for the full command, outputs, and claim boundaries.

For observed-policy generation, see [docs/POLICY_WORKFLOW.md](docs/POLICY_WORKFLOW.md).

## Local Proof Standard

No public claim should ship until the lab can show:

1. Guarded OpenHands command execution runs under pinned source and runtime image.
2. Allowed developer commands still run.
3. A copied and renamed non-policy executable is blocked by identity, not basename.
4. Block events produce supervisor-owned audit records.
5. OpenHands trajectory records the denial from the current run.
6. The result is reproducible from a clean checkout on the same machine.

## Key Boundary

This lab is not a kernel-person branding exercise. It is a governed-agent-execution proof.

The public demo should show runtime enforcement. It should not expose the private governance methodology, frozen evidence packet discipline, authority composition architecture, contamination diagnostics, or richer adjudication logic.
