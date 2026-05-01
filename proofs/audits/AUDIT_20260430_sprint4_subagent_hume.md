# Sprint 4 — Subagent Audit Review (Hume)

Date: 2026-04-30
Auditor: Hume (`019de0b9-2d9c-7e91-8f9a-5418afbe1281`)
Posture: read-only kernel/runtime correctness audit.
Scope: Sprint 4 of `/home/blazingradar/agent-exec-guard-lab`, with focus on `guard/usernotify_exec_guard.c`, Sprint 4 replay/proof artifacts, Sprint 2/Sprint 3 regression posture, and F4 carry-forward discipline.

## Findings

No Critical or High findings.

Medium: F2 is replay-supported but not signal-safe as implemented. `fatal_signal_handler()` calls `snprintf()` from a signal handler before `write()` (`guard/usernotify_exec_guard.c:95`). `write()` is the right primitive, but `snprintf()` is not async-signal-safe, so the `supervisor_exit{reason:killed_by_signal}` guarantee can fail under unlucky runtime state. The replay proves the simple child `SIGTERM` case, not robust signal-context correctness.

Low: child stderr is separated from supervisor audit, but the pipe is not drained after `waitpid(..., WNOHANG)` observes child exit. The loop breaks immediately (`guard/usernotify_exec_guard.c:1081`), then emits `supervisor_exit` (`guard/usernotify_exec_guard.c:1177`). This does not re-open JSON forgery, but it means fast child stderr can be dropped, so the stronger "child stderr is emitted as escaped records" claim is not complete.

Low: `argv_total_count` is capped by `MAX_ARGV_COUNT_SCAN = 256` (`guard/usernotify_exec_guard.c:53`). For argv longer than 256 entries, the field is a scanned count, not the total count. `argv_truncated` still closes the silent-truncation issue for the audited class.

Low: F5 is closed for `/proc/self/exe`, but not for all possible child-context path resolution. `/proc/self/...` is correctly rewritten through `/proc/<pid>/...`, and absolute paths go through `/proc/<pid>/root` (`guard/usernotify_exec_guard.c:773`). Relative paths containing `/` are resolved as `cwd/raw` in the supervisor's view (`guard/usernotify_exec_guard.c:780`), which is weaker under mount/chroot namespace differences.

## Supported Claims

F1 supported: child stderr no longer shares the supervisor audit fd. Parent duplicates audit fd with `F_DUPFD_CLOEXEC` (`guard/usernotify_exec_guard.c:1194`); child stderr is piped and audit fd is closed in the child (`guard/usernotify_exec_guard.c:1224`). Replay shows forged JSON becomes `child_stderr`, not `exec_decision`.

F3/F8 supported: policy parsing is no longer `strstr`-style; malformed `allowed_executables` is rejected fail-closed (`guard/usernotify_exec_guard.c:650`), and output JSON escapes `policy_id`.

F5 supported for the claimed replay case: `/proc/self/exe` resolves to `/usr/bin/python3.12` in the child context in the final Sprint 4 artifact.

F6 supported: `sha256sum` fork/exec is gone; SHA256 uses AF_ALG in-process (`guard/usernotify_exec_guard.c:319`).

F7 supported with the count caveat above: audit records include `argv_truncated` and `argv_total_count` (`guard/usernotify_exec_guard.c:1044`).

Sprint 2/Sprint 3 claims are not visibly regressed: latest Sprint 2 replay is `pass=12 fail=0`, identity matching still uses `(realpath, dev, ino)` (`guard/usernotify_exec_guard.c:862`), execveat remains blocked, and Landlock underlay is still installed in the child before `execvp` (`guard/usernotify_exec_guard.c:1242`).

F4 remains properly deferred: allowed execs still use `SECCOMP_USER_NOTIF_FLAG_CONTINUE` (`guard/usernotify_exec_guard.c:1157`), and the Sprint 4 proof explicitly names the F_CONT TOCTOU caveat as not eliminated.
