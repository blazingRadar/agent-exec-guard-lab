# Source Notes

Date: 2026-04-30

These notes capture the current reasoning before implementation.

## Working Direction

The likely public wedge is a thin runtime enforcement demo for OpenHands-style coding agents:

- prove a real command execution boundary
- use raw Docker first
- integrate with OpenHands only after raw proof passes
- keep the deeper governance methodology private

## Rationale

The demo is attractive because it is concrete:

- default sandbox permits command execution
- stricter runtime policy blocks off-policy execution
- audit output proves the block

This can be explained visually in seconds.

## Important Caution

Do not ship another broad demo that nobody uses.

Before public work:

- run everything locally
- prove it works
- preserve failures
- avoid claims that outrun the proof

## Social / Maintainer Framing

If OpenHands is referenced publicly, frame respectfully:

> OpenHands correctly uses Docker sandboxing. This project explores stricter task-scoped execution policy for autonomous coding-agent workloads.

Avoid:

- "OpenHands is insecure"
- "Docker is broken"
- "we fixed agent security"

## Public / Private Split

Public:

- thin guard
- seccomp/profile plumbing
- hand-written policy
- minimal logs
- demo scripts

Private:

- frozen evidence methodology
- contamination diagnostics
- authority composition
- ATS/IR compiler
- typed refusal taxonomy
- full audit corpus

## Must-Have Before Public Demo

The local proof has to be undeniable:

- baseline command runs
- guarded command blocks
- allowed command still runs
- audit log appears
- reproduction works twice

Nothing public until this is true.
