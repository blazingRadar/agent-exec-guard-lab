# Sprint 1 External Audit Notes

Date: 2026-04-30

These notes preserve external audit feedback received after Sprint 1.

## Audit 1 Summary

Verdict:

- Sprint 1 is a legitimate partial pass.
- Integrity check passed.
- Source and binary SHA256 hashes matched the proof document.
- Implementation was read and judged technically correct for the claimed scope.
- Docker/OpenHands proof remains blocked and correctly unclaimed.

Confirmed strengths:

- BPF filter targets `execve` and `execveat` only.
- `PR_SET_NO_NEW_PRIVS` is set before installing the filter.
- `process_vm_readv` is used to read the executable path.
- `poll()` plus `waitpid(..., WNOHANG)` fixed the supervisor hang.
- `SECCOMP_USER_NOTIF_FLAG_CONTINUE` is used on allow.
- `-EPERM` is used on block.
- audit docs preserve failures honestly.

Key finding:

- basename allowlist is acceptable for Sprint 1 demo proof but is a known bypass vector for production or stronger Sprint 2 claims.

Critical gaps:

- Docker access must be resolved before Docker/OpenHands proof.
- No replay script exists yet.
- Public repo cleanup should happen later, not now.

## Audit 2 Summary

Verdict:

- Sprint 1 allowed claim is accurate:
  - raw local seccomp user-notify guard intercepts `execve` / `execveat`
  - allows a small dev-command set
  - blocks `/bin/rm`
  - blocks nested subprocess attempts
  - emits JSON audit records

Verified:

- source exists
- proof docs exist
- source hash matches proof doc
- binary hash matches proof doc
- recompile succeeds with `gcc -Wall -Wextra -O2`
- safe probes confirmed `/bin/rm` is blocked even with `exec -a git /bin/rm` and Python `os.execv("/bin/rm", ["git", ...])`

Findings:

- High: basename allowlist is bypassable for allowed names.
  - audit reportedly proved a fake executable named `python3` in `/tmp` was allowed through `/usr/bin/env python3`
  - Sprint 2 needs canonical path and ideally `(dev, ino)` identity
- Medium: supervisor is also under the seccomp filter.
  - current supervisor does not exec, so Sprint 1 works
  - future supervisor/adjudicator helper execution could be unexpectedly trapped
  - suggested fix: install filter in child after fork or keep supervisor outside the boundary
- Medium: no `SECCOMP_IOCTL_NOTIF_ID_VALID` check.
  - add validation before trusting request/responding
- Medium: audit output is not JSON-safe.
  - executable paths are interpolated directly
  - add JSON escaping
- Medium: `execveat` is intercepted but not semantically resolved.
  - document conservative handling until fd-backed identity exists
- Low: process string capture is fragile.
  - fixed 4095-byte `process_vm_readv`
  - page-aware read would be stronger
- Low: lab is not a git repo.
  - acceptable privately; initialize before showing anyone

Recommended next gate:

1. canonical path allowlist
2. `(dev, ino)` identity capture for allowed executables
3. JSON-safe audit
4. child-only filter installation
5. replay direct/nested/shell probes
6. then Docker/OpenHands once socket access is solved

## Maintainer Response

Accepted. Sprint 2 should harden the local proof before broadening to OpenHands.

The external audits do not invalidate Sprint 1. They narrow the next claim boundary:

- Sprint 1 proved raw interception and basic policy.
- Sprint 2 must prove identity-aware local policy and replayability.
- Docker/OpenHands remains blocked until Docker access is available.

## Audit 3/4 Combined Summary

Verdict:

- Engineering is real.
- Audit discipline is strong.
- Security framing must be tightened because two trivial bypass classes would be immediately flagged by experienced seccomp reviewers.

Critical finding 1:

- basename allowlist is trivially bypassable.
- Guard code matches only `base_name(path)` against allowed names.
- Demonstrated bypass:

```bash
cp /bin/rm /tmp/git
./bin/usernotify_exec_guard /tmp/git --version
```

Observed:

```text
{"decision":"ALLOW","exe":"/tmp/git",...}
rm (GNU coreutils) 9.4
```

Impact:

- An agent with allowed Python can copy `/bin/rm` to an allowed basename such as `/tmp/git` without triggering `execve`.
- It can then execute `/tmp/git`.
- Symlink bypass has the same shape.
- The current audit trail would record an `ALLOW`, making the log misleading if the claim were framed as security rather than mechanism proof.

Critical finding 2:

- `SECCOMP_USER_NOTIF_FLAG_CONTINUE` is used on ALLOW.
- Kernel documentation warns that `CONTINUE` can create a TOCTOU window for pointer/path-validating policies because the supervisor validates a userspace pointer and then the kernel re-reads it.
- This is not necessarily exploited by accident, but it is known enough that an experienced reviewer will name it.

Recommended Sprint 2 prerequisites:

1. Replace basename match with absolute realpath or device/inode match.
2. Enrich JSON records with pid, argv, timestamp, cwd, realpath, and sha256 of resolved binary.
3. Decide and document TOCTOU posture:
   - either avoid `CONTINUE` with a stronger fd/addfd/re-emit design, or
   - explicitly document residual TOCTOU in the threat model.
4. Externalize policy into `policy.json`.
5. Add supervisor-exit JSON record.

Explicit warning:

- Docker should not be added before these are addressed.
- Putting Docker around a basename-bypass policy would make the demo easier to misread.

What survives cleanly:

- SHAs reproduce.
- BPF filter is correct.
- `PR_SET_NO_NEW_PRIVS` is set.
- supervisor hang fix is sound.
- arch mismatch falls through to `KILL_PROCESS`.
- audit discipline is credible:
  - pre-registered scope
  - claims-still-not-allowed
  - preserved failure
  - realism finding on locale shell helpers

Required tightened claim:

> Sprint 1 applies a hardcoded basename allowlist; basename matching is bypassable by trivial rename or symlink. This is a mechanism proof, not a security claim.
