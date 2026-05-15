# Sprint 2: Identity Hardening Proof

Date: 2026-04-30

## Goal

Harden the Sprint 1 mechanism proof before Docker/OpenHands:

1. Replace basename allow decisions with resolved executable identity.
2. Externalize allowed executable policy.
3. Emit JSON-safe, richer audit records.
4. Keep the supervisor outside the seccomp filter boundary.
5. Add replayable proof scripts and adversarial probes.
6. Document the remaining `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU posture honestly.

## Scope

In scope:

- local non-Docker proof
- identity-aware executable allowlist
- fake-name and symlink bypass probes
- shell/Python nested subprocess probes
- replay script

Out of scope:

- Docker
- OpenHands
- production security claims
- governance/IP logic

## Claim Target

If this sprint passes, the allowed claim is:

> A local seccomp user-notify guard can enforce a file-backed executable identity allowlist, reject basename rename/symlink bypasses, preserve nested `execve` trapping, and emit JSON-safe audit records.

## Claims Still Not Targeted

- Docker proof
- OpenHands proof
- cross-platform support
- complete TOCTOU elimination
- production readiness

## Implementation Summary

Sprint 2 replaced the Sprint 1 hardcoded basename allowlist with:

- file-backed policy: `policy/sprint2.allow.json`
- canonical `realpath()` resolution
- `(dev, ino)` identity comparison
- resolved binary SHA256 in audit records
- JSON escaping for all string fields
- argv capture
- cwd capture
- `supervisor_exit` audit record
- `SECCOMP_IOCTL_NOTIF_ID_VALID` before responding
- child-only seccomp filter installation with Unix socket fd handoff

The supervisor is no longer under the supervised child's seccomp boundary.

## Replay Script

Replay script:

```text
scripts/replay_sprint2_identity.sh
```

The script:

- recompiles the guard
- creates a contained per-run workspace under `proofs/sprint2_runs/`
- runs direct allow/block cases
- runs nested shell/Python block cases
- runs copy-rename bypass case
- runs symlink bypass case
- runs `/usr/bin/env` PATH hijack case
- runs hostile path JSON escaping case
- runs conservative `execveat` block case
- validates JSON audit lines with Python
- records stdout, stderr, exit code, command, summary, and hashes

No `/tmp` workspace is used by the replay script.

## Preserved Failure

First replay run:

```text
proofs/sprint2_runs/sprint2-20260430T220518Z
```

Result:

```text
pass=10 fail=2
```

Cause:

- replay harness polluted its own `PATH` for the env-path bypass case
- JSON validation then invoked the fake `python3` symlink
- fixed by scoping the modified PATH to the guarded command via `env PATH=...`

This was a harness failure, not a guard failure, and is preserved.

## Passing Runs

Passing run 1:

```text
proofs/sprint2_runs/sprint2-20260430T220552Z
pass=11 fail=0
```

Passing run 2:

```text
proofs/sprint2_runs/sprint2-20260430T220610Z
pass=11 fail=0
```

Passing run 3 after adding `execveat` probe:

```text
proofs/sprint2_runs/sprint2-20260430T220722Z
pass=12 fail=0
```

## Key Evidence

Copy-rename bypass probe:

```text
cp /bin/rm work/git
guard work/git --version
```

Observed in audit:

```json
{"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":".../work/git","realpath":".../work/git","sha256":"8e3faaa5eb4a2a4d0e2788fe442bcac6d604be5a0c5a9f09d08f06e3a3fcf570"}
```

The renamed binary did not print `rm (GNU coreutils)`.

`/usr/bin/env` PATH hijack probe:

```text
PATH=work:$PATH guard /usr/bin/env python3 --version
```

Observed:

- `/usr/bin/env` allowed by identity
- `work/python3` resolved to `/usr/bin/rm` through symlink
- second exec blocked with `blocked_executable_identity`

Hostile path JSON probe:

- executable path included a double quote
- JSON audit output parsed successfully

`execveat` probe:

- `/usr/bin/python3` was allowed by identity
- Python invoked syscall `322` / `execveat`
- guard blocked the second syscall with `execveat_not_supported_in_sprint2`
- Python observed `errno=1` / `EPERM`

This preserves the Sprint 2 posture: `execveat` is trapped but not treated as identity-solved.

## Current Honest Claim

> A local seccomp user-notify guard can enforce a file-backed executable identity allowlist, reject basename rename/symlink/PATH-hijack bypasses tested in Sprint 2, preserve nested `execve` trapping, and emit JSON-safe audit records.

It also conservatively blocks the tested `execveat` path rather than claiming fd-relative identity support.

## Remaining Limitations

The allow path still uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE`.

This means Sprint 2 does **not** claim complete TOCTOU elimination for path-based allow decisions. The current posture is:

- identity is checked before allow
- notification id is validated before response
- audit records include realpath, dev, ino, and sha256
- residual pointer/path TOCTOU remains because the kernel re-reads user memory after `CONTINUE`

Future hardening should investigate fd-stable execution, ptrace-mediated execution, or a narrower design that avoids path-based `CONTINUE` for high-risk allows.

## Sprint 2 Verdict

Local identity hardening proof: **PASS**

Docker/OpenHands proof: **STILL BLOCKED / NOT ATTEMPTED**

Public demo readiness: **NO**

The next gate can be either:

- independent audit of Sprint 2 artifacts, or
- Docker access remediation followed by container-only proof, while preserving the TOCTOU limitation.
