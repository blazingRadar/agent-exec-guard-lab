# Sprint 2 Audit

Date: 2026-04-30

## Audit Question

Did Sprint 2 close the Sprint 1 basename-bypass and audit-integrity findings enough to justify moving toward a container proof?

## Verdict

Local identity hardening proof: **PASS**

Docker/OpenHands proof: **NOT ATTEMPTED**

Public demo readiness: **NO**

## What Changed

Sprint 2 replaced the Sprint 1 hardcoded basename allowlist with identity-aware local policy:

- policy moved to `policy/sprint2.allow.json`
- allowed paths resolve through `realpath()`
- allow decisions compare `realpath`, `st_dev`, and `st_ino`
- audit records include pid, syscall, notification id, raw executable, realpath, cwd, dev, ino, sha256, argv, reason, decision, timestamp, and policy id
- string fields are JSON escaped
- supervisor emits `supervisor_exit`
- filter is installed in the child and listener fd is passed back to the supervisor with a Unix socket
- supervisor is no longer under the supervised child seccomp filter
- `SECCOMP_IOCTL_NOTIF_ID_VALID` is checked before response
- `execveat` is blocked conservatively with `execveat_not_supported_in_sprint2`

## Replay Evidence

Replay script:

```text
scripts/replay_sprint2_identity.sh
```

Passing run:

```text
proofs/sprint2_runs/sprint2-20260430T220722Z
pass=12 fail=0
```

Preserved failed harness run:

```text
proofs/sprint2_runs/sprint2-20260430T220518Z
pass=10 fail=2
```

The failed run was a replay harness `PATH` pollution issue, not a guard failure. It is preserved.

## Hashes

Current source and binary hashes from the passing replay:

```text
58b8409de0c53d4be2e742cac11877902b1c6249c9e8a4a06e7b053314a4aae2  guard/usernotify_exec_guard.c
40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415  bin/usernotify_exec_guard
```

## Probes Passed

- `allow_git`: allowed `/usr/bin/git`
- `direct_block_rm`: blocked `/bin/rm`
- `bash_nested_block_rm`: allowed bash, blocked bash child `/bin/rm`
- `python_nested_block_rm`: allowed Python, blocked Python subprocess `/bin/rm`
- `copy_rename_bypass_blocked`: blocked copied `/bin/rm` renamed to `git`
- `symlink_bypass_blocked`: blocked symlink named `python3` resolving to `/bin/rm`
- `env_path_bypass_blocked`: allowed `/usr/bin/env`, blocked PATH-hijacked `python3` resolving to `/bin/rm`
- `json_escape_hostile_path`: emitted valid JSON for path containing a double quote
- `execveat_blocked`: blocked tested `execveat` syscall conservatively

## Claims Now Allowed

> A local seccomp user-notify guard can enforce a file-backed executable identity allowlist, reject the tested basename rename, symlink, and PATH-hijack bypasses, preserve nested `execve` trapping, conservatively block the tested `execveat` path, and emit JSON-safe audit records.

## Claims Still Not Allowed

Do not claim:

- Docker proof
- OpenHands proof
- production readiness
- cross-platform support
- complete TOCTOU elimination
- fd-relative `execveat` identity support
- that path-based `CONTINUE` allows are TOCTOU-hardened

## Remaining Security Limitation

The allow path still uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE`.

That leaves residual TOCTOU risk because the supervisor validates userspace path state before the kernel continues and re-reads the syscall arguments. Sprint 2 improves identity checking and audit trail fidelity, but it does not close this kernel-documented class.

Current posture:

- acceptable for local mechanism/identity proof
- must be disclosed in any threat model
- not enough for a production hardening claim

## Next Gate

Recommended next step:

1. Independent audit of Sprint 2 artifacts.
2. Then remediate Docker access.
3. Then run a container-only proof with the same replay discipline.

Do not jump directly to OpenHands until a raw Docker/container proof passes.
