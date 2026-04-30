# Sprint 1 Audit

Date: 2026-04-30

## Audit Question

Did Sprint 1 prove a local runtime execution boundary strongly enough to justify moving toward Docker/OpenHands proof?

## Verdict

Local non-Docker proof: **PASS**

Docker/OpenHands proof: **BLOCKED**

Overall Sprint 1 verdict: **PARTIAL PASS**

## What Passed

The sprint proved a minimal `SECCOMP_RET_USER_NOTIF` guard can:

- install without libseccomp using raw Linux kernel headers
- intercept `execve` and `execveat`
- allow normal developer commands such as `git`, `python3`, `echo`, and `bash`
- block `/bin/rm` before execution
- block nested subprocess execution from Python
- block child process execution from an allowed shell
- emit JSON decision records
- exit cleanly after the supervisor loop fix

## What Failed Or Was Blocked

Docker was not testable from the current user account:

- Docker CLI is installed.
- Docker daemon access fails with permission denied.
- `/var/run/docker.sock` is owned by `root:docker`.
- current user is not in `docker`.
- passwordless sudo is unavailable.

Therefore no claim about Docker or OpenHands behavior has been proven locally yet.

## Important Implementation Finding

The first guard version made correct ALLOW/BLOCK decisions but hung until timeout because the supervisor waited on the listener after the child exited.

The fix added:

- `poll()` on the seccomp listener
- repeated `waitpid(..., WNOHANG)` checks

This matters because the proof would have been demo-fragile without that fix.

## Important Policy Finding

Allowing `/bin/bash` does not mean a shell session will be smooth under a strict allowlist. A normal login/profile shell attempted helper commands such as:

- `/usr/bin/locale-check`
- `/usr/bin/locale`

Those were blocked because they were not in the hardcoded allowlist.

This is not a failure of the enforcement mechanism. It is a realism finding: useful agent policies need either:

- clean shell launch modes such as `--noprofile --norc`
- broader bootstrap allowlists
- phase-specific policy profiles

## Honest Claim Now Allowed

> A raw local seccomp user-notify guard can enforce below-process-launch policy on this machine: it allows approved developer commands, blocks `/bin/rm`, blocks nested subprocess attempts, and emits JSON audit records.

## Tightened Claim After External Audit

External audits found that the original honest claim can be misread as a security claim. The tighter claim is:

> Sprint 1 applies a hardcoded basename allowlist through a raw local seccomp user-notify guard. It proves interception and decision plumbing, but basename matching is bypassable by trivial rename or symlink. Sprint 1 is a mechanism proof, not a security proof.

This tightened claim supersedes any wording that implies robust command identity.

## Claims Still Not Allowed

Do not claim yet:

- OpenHands has been tested locally
- Docker sandbox integration works
- the guard works inside Docker
- this is ready to publish
- this is production security
- command identity is robust
- basename matching is safe
- the `CONTINUE`-based allow path is TOCTOU-hardened

## Next Gate

Before Sprint 2 can prove OpenHands, Docker access must be resolved by one of:

- add `blazingradar` to the `docker` group and start a new login session
- run the Docker proof with sudo interactively
- use a rootless Docker context if available
- use another local container runtime with equivalent seccomp support

Sprint 2 should not proceed to public demo work until this is resolved.
