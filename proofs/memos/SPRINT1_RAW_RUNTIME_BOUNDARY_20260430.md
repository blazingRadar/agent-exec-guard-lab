# Sprint 1: Raw Runtime Boundary Proof

Date: 2026-04-30

## Goal

Prove the smallest local runtime boundary before touching OpenHands:

1. Docker/default execution can launch normal processes.
2. A guarded runtime can block an off-policy `execve`.
3. Allowed developer commands still run under the guard.
4. Every result is preserved honestly.

## Scope

In scope:

- local host checks
- raw Docker baseline
- minimal local runtime guard proof
- allow/block cases
- audit notes

Out of scope:

- OpenHands integration
- public repo packaging
- claims about production readiness
- governance/IP exposure

## Running Log

### 2026-04-30 Sprint Start

Sprint initialized. No implementation exists yet. First step is environment verification.

### Environment Verification

Host:

- kernel: `Linux loftingWonder 6.17.0-14-generic #14~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Thu Jan 15 15:52:10 UTC 2 x86_64`
- user: `uid=1001(blazingradar) gid=1001(blazingradar) groups=1001(blazingradar),27(sudo),100(users)`
- compiler: `gcc 13.3.0`

Seccomp:

- `/boot/config-$(uname -r)` reports `CONFIG_SECCOMP=y`
- `/boot/config-$(uname -r)` reports `CONFIG_SECCOMP_FILTER=y`
- kernel headers expose `SECCOMP_RET_USER_NOTIF`
- kernel headers expose `SECCOMP_FILTER_FLAG_NEW_LISTENER`
- kernel headers expose `SECCOMP_IOCTL_NOTIF_RECV`

Docker:

- Docker CLI is installed: Docker Engine Community `29.1.3`
- Docker daemon access is blocked for this user:
  - `/var/run/docker.sock` is owned by `root:docker`
  - current user is not in the `docker` group
  - `sudo -n true` fails because sudo requires a password

Dependency note:

- `libseccomp` pkg-config development files are not installed.
- Sprint continued with direct Linux kernel headers and raw BPF instead of libseccomp.

### Implementation

Created a minimal local guard:

- source: `guard/usernotify_exec_guard.c`
- binary: `bin/usernotify_exec_guard`
- source line count: `228`
- source SHA256: `8908182cde2cb877660ceeda27b9ff5ede496eac24cc7979236d89066deb8a95`
- binary SHA256: `29f80ef812a629189592afdb4fcca3c3a146a2ce70c82e20c79510f303cf6b8e`

The guard:

- installs a seccomp filter with `SECCOMP_FILTER_FLAG_NEW_LISTENER`
- intercepts `execve` and `execveat`
- reads the requested executable path from the child process
- allows a small hardcoded development command list
- blocks unlisted executable paths with `EPERM`
- emits one JSON audit line per decision

This is intentionally a minimal public-demo-shaped guard. It does not expose governance logic.

### First Implementation Finding

The first compiled version made correct ALLOW/BLOCK decisions but did not exit cleanly after the child exited. The supervisor loop blocked waiting for additional seccomp notifications.

Fix:

- added `poll()` around the listener
- checked `waitpid(..., WNOHANG)` each loop

This failure was preserved because it is relevant to proof quality.

### Baseline Local Proof

Command:

```bash
/bin/rm --version | head -1; printf 'exit=%s\n' "$?"
```

Observed:

```text
rm (GNU coreutils) 9.4
exit=0
```

Interpretation:

- unguarded local execution can launch `/bin/rm`
- this is not Docker proof, but it establishes the local baseline behavior

### Guarded Proof: Direct Block

Command:

```bash
timeout 5 ./bin/usernotify_exec_guard /bin/rm --version; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
execvp: Operation not permitted
exit=126
```

Interpretation:

- the guard intercepted the `execve`
- `/bin/rm` was blocked before execution
- the block produced a JSON audit record

### Guarded Proof: Allowed Commands

Command:

```bash
timeout 5 ./bin/usernotify_exec_guard /usr/bin/git --version; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/usr/bin/git","policy":"sprint1_hardcoded_allowlist"}
git version 2.43.0
exit=0
```

Command:

```bash
timeout 5 ./bin/usernotify_exec_guard /usr/bin/python3 --version; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/usr/bin/python3","policy":"sprint1_hardcoded_allowlist"}
Python 3.12.3
exit=0
```

Interpretation:

- allowed developer commands still run under the guard

### Guarded Proof: Nested Subprocess Block

Command:

```bash
timeout 5 ./bin/usernotify_exec_guard /usr/bin/python3 -c 'import subprocess; subprocess.run(["/bin/rm", "--version"], check=True)'; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/usr/bin/python3","policy":"sprint1_hardcoded_allowlist"}
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
PermissionError: [Errno 1] Operation not permitted: '/bin/rm'
exit=1
```

Interpretation:

- the guard allowed Python itself
- a nested subprocess attempt to launch `/bin/rm` was blocked
- this is stronger than blocking only the initial command

### Repeat Run

The allow/block/nested-block cases were repeated successfully:

- `/bin/echo` allowed, exit `0`
- `/bin/rm` blocked, exit `126`
- `/usr/bin/python3` allowed, nested `/bin/rm` blocked, exit `1`

### Guarded Proof: Shell Subprocess Block

Command:

```bash
timeout 5 ./bin/usernotify_exec_guard /bin/bash --noprofile --norc -lc '/bin/rm --version'; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/bin/bash","policy":"sprint1_hardcoded_allowlist"}
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
/bin/bash: line 1: /bin/rm: Operation not permitted
exit=126
```

Interpretation:

- the shell was allowed
- the shell's attempted child process was blocked
- this supports the "below the model / below the shell command text" claim for the local proof

Additional note:

- running `/bin/bash -lc ...` without `--noprofile --norc` also intercepted profile startup helpers such as `/usr/bin/locale-check` and `/usr/bin/locale`
- that is a useful realism finding: practical policies need either a broader dev allowlist or a clean shell launch mode

## Sprint 1 Interim Verdict

Local non-Docker runtime boundary mechanism proof: **PASS**

Docker/OpenHands proof: **BLOCKED**

Reason:

- Docker daemon access is unavailable to the current user.
- User is not in the `docker` group and passwordless sudo is unavailable.

Honest current claim:

> Sprint 1 applies a hardcoded basename allowlist through a raw local seccomp user-notify guard. It proves interception and decision plumbing, but basename matching is bypassable by trivial rename or symlink. Sprint 1 is a mechanism proof, not a security proof.

Not yet claimable:

> This has been proven inside Docker or OpenHands on this machine.

Also not yet claimable:

> Robust executable identity has been solved.

> The `CONTINUE` allow path is TOCTOU-hardened.
