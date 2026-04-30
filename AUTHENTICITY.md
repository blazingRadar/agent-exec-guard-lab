# Authenticity and Claim Discipline

This repository is a lab record for the Agent Exec Guard work.

The repo intentionally preserves:

- sprint memos
- command logs
- independent audit notes
- failed replay runs
- proof scratch sources and outputs
- binaries used in local proof runs

Do not remove failures to make the work look cleaner. Failed runs are part of the evidence chain.

## Claim Discipline

Allowed claims must be backed by a replay artifact, proof memo, source hash, or command log in this repository.

Do not claim:

- production sandbox security
- Docker/OpenHands integration
- complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU elimination
- fd-stable execution
- read/write/network restriction
- general Linux portability beyond the tested host

Current strongest supported framing:

> Seccomp decides the requested executable identity; Landlock enforces the allowed executable universe underneath it.

Current strongest supported technical claim:

> On the tested Linux host, a local seccomp user-notify execution guard preserves file-backed executable identity decisions, adds a child-inherited Landlock execute underlay, and emits supervisor-owned audit records that the supervised child cannot forge by writing JSON to stderr.

## Carry-Forward Rule

Every future sprint memo should begin with a carry-forward open-items table. Each prior finding must be marked:

- closed this sprint
- deferred with reason
- declared out of scope with reason

If a claim is not proven, it must be named as not proven.
