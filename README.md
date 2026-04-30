# Agent Exec Guard Lab

Private lab for validating a minimal runtime execution guard for AI coding agents before any public demo or repo is shipped.

## Purpose

Build tangible local proof that an OpenHands-style coding agent running in a Docker sandbox can be constrained by a stricter runtime execution policy than Docker's default compatibility profile.

The public artifact, if validated, should be a thin demo:

- custom seccomp profile or equivalent hard runtime boundary
- minimal adjudicator
- simple policy file
- local proof scripts
- OpenHands integration notes
- short video-ready reproduction

The deeper governance system remains private.

## Current Status

- Lab initialized: 2026-04-30
- Implementation status: not started
- Public demo status: blocked until local proof passes
- Primary target: OpenHands-style Docker sandbox execution
- Proof standard: reproduce locally before publishing anything

## Local Proof Standard

No public claim should ship until the lab can show:

1. Baseline container or OpenHands sandbox allows the target execution under default settings.
2. Guarded execution blocks the same target action.
3. Allowed developer commands still run.
4. Block events produce a clear local audit record.
5. The result is reproducible from a clean checkout on the same machine.

## Key Boundary

This lab is not a kernel-person branding exercise. It is a governed-agent-execution proof.

The public demo should show runtime enforcement. It should not expose the private governance methodology, frozen evidence packet discipline, authority composition architecture, contamination diagnostics, or richer adjudication logic.
