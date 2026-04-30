# Sprint 4 — Independent Audit Review (Auditor B)

Date: 2026-04-30
Auditor: Auditor B (independent adversarial pass on Sprint 4 self-audit `SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`).
Posture: re-derive provenance, re-run replay harnesses, reproduce each Sprint 2 finding live, look for new bypass surfaces introduced by Sprint 4 fixes, check carry-forward discipline against the recommendation made at the end of the Sprint 3 audit.
Source of record: live commands run on this machine; SHAs re-derived; F1-F8 reproductions executed against the freshly rebuilt binary.

A parallel Auditor A is running the same brief independently. I did not coordinate.

---

## 1. Audit Question

Did Sprint 4 close the six Sprint 2 audit-integrity findings (F1, F2, F3, F5, F6, F7) plus F8 that were carried forward through Sprint 3? Is F4 honestly carried forward as deferred, not silently dropped? Did the fixes introduce new bypass surfaces or regressions? Do Sprint 1/2/3 invariants still hold?

## 2. Verdict

**Sprint 4 closes the reproduced classes of F1, F2, F3, F5, F6, F7, and F8 cleanly. Live regression tests against the Sprint 3 binary stop reproducing; live tests against the Sprint 4 binary now show the fix. Sprint 1/2/3 invariants are intact. F4 is carried forward explicitly. The headline as written in `SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md` is accurate.**

The Sprint 3 audit's discipline recommendation — "every sprint memo should lead with a Carry-forward Open Items section" — was adopted: the Sprint 4 memo opens with that exact section header, lists F1-F8 with sprint-4-status per row, and explicitly marks F4 as Deferred with a forward-looking pointer to Sprint 5+.

Two minor observations worth noting (neither rises to a finding):

- The signal handler at lines 95-113 calls `snprintf` and is technically not async-signal-safe per POSIX, though glibc's implementation is safe in practice for this format. `sigaction` does not add SIGTERM/SIGINT/SIGHUP to its own `sa_mask`, so a second fatal signal arriving during the handler is not blocked; in practice the `_exit(128+signo)` reaches before any reentry I could trigger.
- The parser's `\uXXXX` escape handler at lines 491-500 collapses any unicode escape to the literal character `?`. This is a parser correctness gap rather than a security gap because policy files are operator-controlled, but a `policy_id` field with `é` would silently round-trip as `?` in the audit stream. Worth fixing in Sprint 5 if anyone ever writes a localized `policy_id`.

The honest one-line summary of Sprint 4's actual state:

> "Sprint 4 closes the Sprint 2 audit-integrity carry-forward (F1, F2, F3, F5, F6, F7, F8) for the reproduced classes. The supervisor audit stream is moved to a `F_DUPFD_CLOEXEC`-duplicated fd that the child closes before execve, child stderr is emitted as escaped `child_stderr` records, SIGTERM/INT/HUP emit `supervisor_exit{reason:killed_by_signal}`, the policy parser is replaced with a strict in-process recursive-descent JSON parser, `/proc/self/...` resolves through `/proc/<child_pid>/...`, SHA256 uses Linux AF_ALG instead of fork+exec to `/usr/bin/sha256sum`, and argv records emit `argv_truncated` and `argv_total_count`. The 12-case Sprint 2 replay still passes (pass=12 fail=0). The 14-case Sprint 4 replay passes (pass=14 fail=0). F4 (`SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU) remains explicitly deferred."

Recommend: Sprint 4 is **kept**. Sprint 5 prerequisites are listed below.

---

## 3. What Verified Clean Independently

### 3.1 Re-derived hashes

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard scripts/replay_sprint4_audit_integrity.sh scripts/replay_sprint2_identity.sh
4d59cb357cea8577057ebb861294f1623768e5d973e0bfd3be80e573792e3d07  guard/usernotify_exec_guard.c
0bb35fd4ab75dc28aa9e1e9334dbee3646b25bb1902117abfe94f12ad536b61c  bin/usernotify_exec_guard
afddc594ae1716aaed54725d4a346cdcfa351a54b881fb8a0b89719c86839d4a  scripts/replay_sprint4_audit_integrity.sh
a7ae211593b2241614bf0536130042ebe83eb70fba932bc364559386bb51b9d6  scripts/replay_sprint2_identity.sh
$ wc -l guard/usernotify_exec_guard.c
1258 guard/usernotify_exec_guard.c
```

All four hashes match the Sprint 4 self-claims byte-for-byte. Source grew from 793 (Sprint 3) to 1258 — **+465 lines**, consistent with the additions: signal handler + dedicated audit fd + child stderr pipe handling + recursive-descent JSON parser + child-pid path rewriter + AF_ALG SHA256 + argv_truncated/argv_total_count plumbing.

### 3.2 Compiler discipline

```
$ gcc -Wall -Wextra -fanalyzer -O2 -o /tmp/guard_analyzer_check guard/usernotify_exec_guard.c
$ echo $?
0
```

`-fanalyzer` clean compile reproduced.

### 3.3 Replay harnesses, live re-run

Sprint 4 audit-integrity replay (this audit re-ran it):

```
$ bash scripts/replay_sprint4_audit_integrity.sh
PASS compile gcc clean
PASS f1_forged_stderr_is_child_stderr exit=0
PASS f1_forged_stderr_demoted forged JSON escaped as child_stderr
PASS f1_noise_cannot_prefix_supervisor_json exit=0
PASS f1_noise_prefix_closed no child prefix on supervisor JSON
PASS f2_signal_exit_record exit=143
PASS f2_signal_exit_record_present killed_by_signal recorded
PASS f3_policy_string_rejected exit=2
PASS f3_policy_string_rejected_reason malformed policy failed closed
PASS f5_proc_self_exe_child_context exit=0
PASS f5_proc_self_exe_resolved_to_child numeric proc resolution used
PASS f6_no_sha256sum_exec source no longer references sha256sum
PASS f7_argv_truncation_marked exit=0
PASS f7_argv_truncation_fields argv truncation metadata emitted
pass=14 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260430T233008Z
```

Sprint 2 identity replay against the Sprint 4 binary:

```
$ bash scripts/replay_sprint2_identity.sh
PASS compile gcc clean
PASS allow_git ... PASS direct_block_rm ... PASS bash_nested_block_rm ...
PASS python_nested_block_rm ... PASS copy_rename_bypass_blocked ...
PASS symlink_bypass_blocked ... PASS env_path_bypass_blocked ...
PASS json_escape_hostile_path ... PASS execveat_blocked
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T233011Z
```

Both replays match the self-claimed numbers.

### 3.4 F1-F8 closure verifications (live, exact reproduction commands)

#### F1 — audit log forgery via shared stderr — **CLOSED**

Same Python `sys.stderr.write("\n{...exec_decision...}\n")` payload from `AUDIT_20260430_sprint2_independent_review_a.md`:

```
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import sys
sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_S4\"}\n")
sys.stderr.flush()'
{"event":"exec_decision",...,"raw_exe":"/usr/bin/python3","decision":"ALLOW",...}
{"event":"child_stderr",...,"data":"\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_S4\"}\n"}
{"event":"supervisor_exit",...,"child_exit":0}
```

The forged JSON is wrapped inside a `child_stderr` record with the entire payload JSON-escaped in the `data` field. There is no `exec_decision` record with `"reason":"FORGED_S4"` in the stream (verified via `grep -c '"reason":"FORGED_S4"' = 0`).

Architecture, verified by reading the source:

- `audit_fd = fcntl(STDERR_FILENO, F_DUPFD_CLOEXEC, 3)` at line 1194 — the supervisor's audit stream is duplicated to a fresh `O_CLOEXEC` fd ≥3 *before* fork.
- A `pipe2(child_stderr, O_CLOEXEC)` is created at line 1211; the child's read end is closed in the parent and the write end is `dup2`'d over `STDERR_FILENO` in the child at line 1227.
- The child explicitly `close(audit_fd)` at line 1231 before the seccomp listener install.
- I verified the child cannot reach the supervisor audit fd by attempting `os.write(fd, ...)` for `fd in range(3, 20)` — every one returns `EBADF`. The `O_CLOEXEC` flag is also a backstop: even if the child somehow forgot to close, `execve` would close it.

#### F2 — supervisor killable by child — **CLOSED for SIGTERM/INT/HUP**

```
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os, signal
os.kill(os.getppid(), signal.SIGTERM)'
{"event":"exec_decision","decision":"ALLOW",...}
{"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGTERM"}
exit=143
```

SIGINT and SIGHUP behave identically: each emits `supervisor_exit{reason:killed_by_signal,signal:"<NAME>"}` before `_exit(128+signo)`.

SIGKILL is uncatchable. I tested it (`os.kill(os.getppid(), signal.SIGKILL)`) and confirmed there is no `supervisor_exit` record. The Sprint 4 memo correctly does not claim SIGKILL coverage. This is a kernel-level limitation, not a guard bug. As a side benefit: when the supervisor dies (SIGKILL or otherwise), subsequent execve attempts in the child return ENOSYS (verified live), so the post-supervisor-death execve surface is fail-closed at the kernel level.

#### F3 — policy parser fail-open — **CLOSED for reproduced class and several adjacent classes**

Exact Sprint 2 spoof reproduction:

```
$ cat > /tmp/spoof_s4.policy.json <<'EOF'
{"policy_id":"spoof","allowed_executables":"should_be_array","extra":["/bin/echo"],"more_paths":["/bin/rm"]}
EOF
$ ./bin/usernotify_exec_guard --policy /tmp/spoof_s4.policy.json /bin/echo SPOOF
policy JSON parse error: allowed_executables must be array
exit=2
```

I also probed adjacent failure modes the Sprint 4 memo does not enumerate:

| Variant | Behavior | Exit |
|---|---|---|
| Top-level array `["/bin/echo"]` | `policy JSON parse error: root must be object` | 2 |
| `allowed_executables: 42` | `allowed_executables must be array` | 2 |
| `allowed_executables: []` | `policy has no allowed executable paths` | 2 |
| missing `allowed_executables` key | `policy has no allowed executable paths` | 2 |
| relative path `bin/echo` | `allowed_executables entries must be absolute paths` | 2 |
| trailing data after `}` | `trailing data after root object` | 2 |

All fail-closed. The parser is hand-rolled recursive-descent (lines 442-755), no external library, no malloc beyond a single `slurp_file` allocation capped at 1 MiB. No CVE surface to inherit.

#### F8 — escaped quote in `policy_id` — **CLOSED (subsumed by F3)**

```
$ cat > /tmp/escape_quote.policy.json <<'EOF'
{"policy_id":"abc\"def","allowed_executables":["/bin/echo"]}
EOF
$ ./bin/usernotify_exec_guard --policy /tmp/escape_quote.policy.json /bin/echo F8_TEST
{...,"policy_id":"abc\"def",...,"decision":"ALLOW",...}
```

The parser correctly handles the `\"` escape in the input (parsed in-place to a literal `"` in the C string), and the output `json_escape` re-escapes it on the way out, producing valid JSON with `policy_id` round-tripping as `abc"def`. The provenance corruption that Sprint 2 audit A demonstrated is closed.

#### F5 — `/proc/self/exe` namespace — **CLOSED for nested case**

```
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os
os.execv("/proc/self/exe", ["/proc/self/exe", "--version"])'
{"event":"exec_decision",...,"raw_exe":"/usr/bin/python3","realpath":"/usr/bin/python3.12",...}
{"event":"exec_decision",...,"raw_exe":"/proc/self/exe","realpath":"/usr/bin/python3.12",...}
Python 3.12.3
```

The nested `os.execv("/proc/self/exe")` inside the child is correctly recorded with `realpath:/usr/bin/python3.12` — the **child's** actual exe at that moment, not the supervisor's binary. The Sprint 3 regression at `/usr/bin/python3` resolved-to-supervisor-binary is gone.

Subtle note: `/proc/self/exe` invoked **directly as the first argument** still records `realpath: bin/usernotify_exec_guard` because at the moment of the very first execve notification, the child has fork()'d but not yet execve'd, so `/proc/<child_pid>/exe` is still the supervisor binary. This is the kernel's truthful answer (the child literally is still executing the supervisor binary at that point) and the policy correctly BLOCKs it (the supervisor binary is not on the allowlist). The Sprint 4 memo's claim ("Closed for reproduced nested child case") is accurate; it explicitly does not claim the direct-/proc/self/exe-as-first-argv case maps to the *intended* target, which would be physically impossible given that no execve has happened yet.

The pid in `req->pid` is kernel-supplied and `notification_id_valid` is checked after `decide_exec` (line 1150), so a pid-recycle race forces BLOCK. Defensive.

#### F6 — SHA256 inlined via AF_ALG — **CLOSED**

```
$ grep -nE 'sha256sum|/usr/bin/sha256' guard/usernotify_exec_guard.c
(no hits)
$ strace -f -e trace=execve,socket,bind,accept4 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/git --version 2>&1 | grep -E 'sha256sum|AF_ALG' | head -10
socket(AF_ALG, SOCK_SEQPACKET|SOCK_CLOEXEC, 0) = 4
bind(4, {sa_family=AF_ALG, salg_type="hash", ..., salg_name="sha256"}, 88) = 0
accept4(4, NULL, NULL, SOCK_CLOEXEC) = 5
... [no execve to /usr/bin/sha256sum] ...
```

Source no longer references `sha256sum`. AF_ALG path is at lines 319-385. Hash output verified independently to match `sha256sum` on a known input (`b94d27b9...` for `"hello world"`).

Three observations on the AF_ALG implementation:

1. The supervisor opens a fresh AF_ALG socket+bind+accept4 per `file_sha256` call (one per policy entry at startup, plus one per child execve check). That's ~10+ socket calls per guard invocation. A persistent socket would be cheaper, but the current design avoids leaking a long-lived alg socket fd across fork. Not a bug; a perf tradeoff.
2. AF_ALG returns `SOCK_CLOEXEC` correctly — child cannot inherit. Verified.
3. Fallback when AF_ALG is unavailable: `file_sha256` returns false, the caller does *not* check the return value, and the `sha256` field in the audit record stays as the literal string `"unavailable"`. The identity decision (`policy_allows_identity`, line 862) uses `dev`+`ino`+`real_path`, **not** SHA256. So an AF_ALG-less environment would still get correct ALLOW/BLOCK decisions; only the audit-record SHA field would be informational-degraded. Sprint 4 memo's "Linux AF_ALG SHA256 is Linux-specific" caveat under "Claims Still Not Allowed" is appropriate.

#### F7 — argv truncation markers — **CLOSED**

```
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /bin/echo a b c d e f g h i j k l m n o p
{...,"argv":["/bin/echo","a","b","c","d","e","f","g"],"argv_truncated":true,"argv_total_count":17,...}

$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /bin/echo a b c
{...,"argv":["/bin/echo","a","b","c"],"argv_truncated":false,"argv_total_count":4,...}

$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /bin/echo "<1024 X bytes>"
argv[1] length: 511 ; argv_truncated: True ; argv_total_count: 2
```

Three behaviors confirmed:

- `argv_total_count` is the actual scanned count (capped only by `MAX_ARGV_COUNT_SCAN=256`), not capped at `MAX_ARGV_CAPTURE=8`. So a downstream consumer can see "argv_total_count=17, argv array of 8" and know exactly how many were dropped.
- `argv_truncated:false` when the count is ≤ 8 and no per-arg truncation occurred.
- Per-arg truncation (>511 bytes per single arg) also flips `argv_truncated:true`.

Hostile bytes (`\n`, `\t`, embedded `"`, control chars) round-trip via `json_escape` correctly; downstream `json.loads` consumes every line cleanly (verified live).

### 3.5 Sprint 1, 2, 3 invariants — all hold against Sprint 4 binary

| Invariant | Result |
|---|---|
| Sprint 1: `cp /bin/rm /tmp/git_audit_b` → BLOCK | BLOCK (`reason: blocked_executable_identity`, exit 126) |
| Sprint 1: symlink `/tmp/python3_audit_b → /bin/rm` → BLOCK | BLOCK (realpath=`/usr/bin/rm`, exit 126) |
| Sprint 1: PATH-hijack `env PATH=/tmp:... /usr/bin/env python3_audit_b` → BLOCK | BLOCK (env runs but exec of `/tmp/python3_audit_b` is BLOCKed) |
| Sprint 2: 12-case identity replay | pass=12 fail=0 |
| Sprint 3: hardlink at non-allowed path → BLOCK | BLOCK (realpath=hardlink path, exit 126) |
| Sprint 3: Landlock layer present | `install_landlock_execute_underlay` still wired in child branch at line 1242, runs after listener fd is sent |

---

## 4. New Findings Introduced by Sprint 4 Fixes

I tried to find a new bypass class introduced by each fix. None rose to the level of a finding. Two minor observations and one pure-correctness quirk:

### 4.1 Signal handler is technically not async-signal-safe (minor, not exploitable)

`fatal_signal_handler` at lines 95-113 calls `snprintf` (technically not async-signal-safe per POSIX, though glibc's `snprintf` is safe in practice for this format — no float, no locale, no malloc). `write` and `_exit` are async-signal-safe.

`install_signal_handlers` at line 115 sets `sa.sa_mask = sigemptyset()` and `sa.sa_flags = 0`. POSIX guarantees the signal being handled is masked (so SIGTERM cannot interrupt its own handler), but **other** fatal signals are not masked. In theory, a SIGTERM-handler in flight could be interrupted by SIGINT, leading to two interleaved `write` calls or two `_exit` calls. In practice my dual-signal stress test produced exactly one `supervisor_exit` record, because `_exit` reaches before the second handler can fire. Not exploitable, but `sa_mask` should ideally include all three signals.

Recommend: add `sigaddset(&sa.sa_mask, SIGTERM); sigaddset(&sa.sa_mask, SIGINT); sigaddset(&sa.sa_mask, SIGHUP);` and consider `signal-safe` formatting (manual integer-to-string instead of `snprintf`). One-line fix; not blocking Sprint 5.

### 4.2 Parser `\u` escape collapses to `?` (correctness, not security)

`parse_json_string` at lines 491-500 consumes the four hex digits after `\u` but emits `?` instead of decoding to UTF-8. So a `policy_id: "é"` is parsed as `policy_id: "?"` and re-emitted as `?` in the audit JSON. This is a parser correctness gap, not a security issue (policy files are operator-controlled, and the stored byte is a printable ASCII `?` which won't break JSON), but it's an incorrect implementation of the JSON spec. Worth fixing alongside the surrogate-pair handling if Sprint 5 needs i18n in policy_id.

### 4.3 Per-call AF_ALG socket setup (perf, not security)

The supervisor opens, binds, and accepts a fresh AF_ALG socket per `file_sha256` call. ~10 socket-class syscalls per guard run is fine for a guard at human-typing rate but may be noticeable in a build-farm scenario. No security impact.

### 4.4 What I tested that did NOT find a regression

- Writing to fd 3, 4, 5, …, 19 from the child to forge supervisor records: all return `EBADF`. The `audit_fd` is closed by the child explicitly and is `O_CLOEXEC` as a backstop.
- 5KB child stderr write split across read boundaries: 5 chunks emitted, all 5000 bytes preserved as JSON-escaped `data` fields. Each chunk is a complete JSON record.
- Chunk-boundary forgery (child writes `"}\n{"event":"exec_decision",...}\n` to stderr): the entire payload is JSON-escaped within the `data` field of a `child_stderr` envelope. No forged `exec_decision` produced.
- Supervisor death mid-syscall: post-death execve attempts in the child return `ENOSYS` (kernel default when no listener is attached). Fail-closed for execve, even though the audit stream is gone.
- `notif_id_valid` check is performed after `decide_exec`, so a pid-recycle race forces BLOCK. Defensive.
- Malformed policies (six adjacent classes beyond the Sprint 2 reproducer) all fail-closed at exit=2.

---

## 5. Carry-Forward / Discipline Observations

The Sprint 3 audit explicitly recommended:

> "every sprint memo should lead with a **'Carry-forward Open Items'** section listing all unclosed findings from the prior sprint by name and current status (closed-this-sprint / deferred-to-next / declared-out-of-scope)."

The Sprint 4 memo does this:

- The header at line 7 reads `## Carry-Forward Open Items`.
- All eight findings (F1-F8) are listed by ID with sprint-4 status: F1, F2, F3, F5, F6, F7, F8 marked Closed (with hedging language about "for reproduced class"); F4 marked Deferred with a forward pointer ("Sprint 5+ architecture work").
- The status column is honest about denial-of-service vs survival ("This is still denial-of-service, not survival" for F2), about parser scope ("Closed for reproduced class … strict for the current policy schema; it is not a general-purpose JSON library" appears in Claims Still Not Allowed), and about F5 nested vs direct ("Closed for reproduced nested child case").

The "Claims Still Not Allowed" list at lines 110-118 retains the appropriate caveats:

- Docker/OpenHands integration unproven.
- Not production sandbox security.
- F4 / `F_CONT` TOCTOU not fully eliminated.
- Signal handling records death; doesn't prevent DoS.
- Parser is schema-specific.
- AF_ALG is Linux-specific.
- Landlock loader paths are x86-64-oriented.
- Read/write/network/builtin/already-open-fd surfaces are out of scope.

This is the discipline the Sprint 3 audit asked for. Adopted.

### 5.1 Failed-run preservation

The first Sprint 4 replay (`proofs/sprint4_runs/sprint4-20260430T232423Z`) reported `pass=13 fail=1`, with the single FAIL on `f5_proc_self_exe_resolved_to_child` because the harness expected `/usr/bin/python3` but `realpath /usr/bin/python3 → /usr/bin/python3.12`. The harness was corrected to dereference the symlink before comparing, and the second run (`sprint4-20260430T232441Z`) returned `pass=14 fail=0`. The failed run directory is preserved on disk; the Sprint 4 command log explains the discrepancy. This is the harness-expectation issue the brief mentioned, and it is honestly documented.

---

## 6. F4 Residual Posture

F4 is `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU. The supervisor decides ALLOW based on the path that was passed in the original execve, then sets `resp.flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE` (line 1157). The kernel re-resolves the path at exec time, so a child that swaps the path between decision and CONTINUE-resume can land on a different binary. Sprint 3 Landlock narrows this to "swap to *another allowlisted* binary" because Landlock denies execute on non-policy paths. The remaining residual is: a child can swap between two allowlisted binaries (e.g. `/usr/bin/git` ↔ `/usr/bin/python3`), which Landlock allows. No bypass to non-policy executables.

Sprint 4 does not change F4. The memo correctly carries it as Deferred. The architectural fix is `SECCOMP_IOCTL_NOTIF_ADDFD` (Φ_B in the Sprint 3 fix-path analyses), which would let the supervisor open the resolved binary, hand the child a stable fd, and force exec via that fd — eliminating the post-decision path-resolution race. That is Sprint 5+ architecture work.

The Sprint 4 deferral framing is accurate.

---

## 7. Sprint 5 Prerequisites (audit-derived)

From this audit:

1. **(optional, low priority) Tighten signal handler**: add SIGTERM/INT/HUP to `sa_mask`; consider replacing `snprintf` with manual integer-to-string for full POSIX async-signal-safety. One-line fix.
2. **(optional, low priority) Parser `\u` decode**: implement actual UTF-8 decoding for `\uXXXX` escapes plus surrogate pair handling, or document the limitation in the policy schema.
3. **F4 architectural close**: prototype `SECCOMP_IOCTL_NOTIF_ADDFD` (Φ_B) to eliminate the path-swap race. This is the "real" Sprint 5+ item the memo points at.
4. **Docker/OpenHands integration**: as the Sprint 4 memo notes, the next blocker is "can this exact guard shape run under the target agent runtime without breaking normal workflows?" That requires (a) a containerized guard build, (b) verification that the seccomp-listener fd flow survives the Docker entrypoint chain, (c) verification that Landlock works inside a container, and (d) policy schema for Docker volume layout.
5. **Optional: persistent AF_ALG socket** for perf if needed; not required for correctness.

---

## 8. Honest Claim That Should Replace the Sprint 4 Headline

The Sprint 4 self-claim under "Claim Now Allowed":

> "A local seccomp user-notify execution guard can preserve Sprint 2 identity decisions, preserve Sprint 3 Landlock execute-underlay behavior, and emit audit records on a supervisor-owned stream that the supervised child cannot forge by writing JSON to stderr. It records signal-kill termination, rejects the reproduced malformed-policy fail-open case, resolves /proc/self/exe from the child process context for the reproduced nested case, computes SHA256 in-process, and marks argv truncation."

**Current claim is accurate.** No tightening required.

The qualifiers are honest where they matter (`reproduced malformed-policy fail-open case`, `reproduced nested case`, `signal-kill termination` — implicitly excluding SIGKILL), and the "Claims Still Not Allowed" list properly excludes Docker/OpenHands, production sandbox guarantees, F4, DoS prevention, general-purpose JSON parsing, non-Linux portability, and non-execute syscall surface.

If anything, the claim could be slightly expanded to acknowledge that Sprint 4 *also* closes F8 (escaped-quote provenance corruption) by virtue of the F3 parser replacement — but the Carry-Forward Open Items table already documents this at row F8, so the omission from the headline is not a discipline violation.

---

## 9. Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

# Re-derive provenance (matches Sprint 4 self-claims)
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
          scripts/replay_sprint4_audit_integrity.sh scripts/replay_sprint2_identity.sh
  -> 4d59cb357cea8577057ebb861294f1623768e5d973e0bfd3be80e573792e3d07  guard/usernotify_exec_guard.c
  -> 0bb35fd4ab75dc28aa9e1e9334dbee3646b25bb1902117abfe94f12ad536b61c  bin/usernotify_exec_guard
  -> afddc594ae1716aaed54725d4a346cdcfa351a54b881fb8a0b89719c86839d4a  scripts/replay_sprint4_audit_integrity.sh
  -> a7ae211593b2241614bf0536130042ebe83eb70fba932bc364559386bb51b9d6  scripts/replay_sprint2_identity.sh
wc -l guard/usernotify_exec_guard.c
  -> 1258 (+465 lines vs Sprint 3's 793)

# -fanalyzer clean
gcc -Wall -Wextra -fanalyzer -O2 -o /tmp/guard_analyzer_check guard/usernotify_exec_guard.c
  -> exit 0
rm -f /tmp/guard_analyzer_check

# Replay reruns clean against Sprint 4 binary
bash scripts/replay_sprint4_audit_integrity.sh
  -> pass=14 fail=0  run_root=proofs/sprint4_runs/sprint4-20260430T233008Z
bash scripts/replay_sprint2_identity.sh
  -> pass=12 fail=0  run_root=proofs/sprint2_runs/sprint2-20260430T233011Z

# F1 — audit forgery now demoted to child_stderr envelope
./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_S4\"}\n")'
  -> child_stderr record contains escaped JSON; no exec_decision with reason=FORGED_S4

# F1 — fd-guess forgery: child cannot reach audit fd
./bin/usernotify_exec_guard ... /usr/bin/python3 -c \
  'import os
   for fd in range(3, 20):
     try: os.write(fd, b"FORGE_FD_"+str(fd).encode()+b"\n")
     except OSError: pass'
  -> all writes EBADF; no FORGE_FD_* in audit stream

# F2 — SIGTERM/SIGINT/SIGHUP each emit supervisor_exit{killed_by_signal}
./bin/usernotify_exec_guard ... /usr/bin/python3 -c 'import os, signal; os.kill(os.getppid(), signal.SIGTERM)'
  -> {"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGTERM"}; exit=143
(SIGINT, SIGHUP analogous)

# F2 — SIGKILL gap acknowledged (kernel-uncatchable, no record)
./bin/usernotify_exec_guard ... /usr/bin/python3 -c 'import os, signal; os.kill(os.getppid(), signal.SIGKILL)'
  -> no supervisor_exit record (kernel limitation)

# F2 — post-death execve in child returns ENOSYS (fail-closed)
./bin/usernotify_exec_guard ... /usr/bin/python3 -c \
  'import os, signal, time, subprocess
   os.kill(os.getppid(), signal.SIGTERM); time.sleep(0.05)
   subprocess.run(["/bin/echo", "after"])'
  -> Errno 38 Function not implemented; supervisor_exit record was emitted prior

# F3 — exact Sprint 2 spoof: now fails closed
echo '{"policy_id":"spoof","allowed_executables":"should_be_array","extra":["/bin/echo"],"more_paths":["/bin/rm"]}' > /tmp/spoof_s4.policy.json
./bin/usernotify_exec_guard --policy /tmp/spoof_s4.policy.json /bin/echo SPOOF
  -> policy JSON parse error: allowed_executables must be array; exit=2

# F3 — adjacent failure modes (top-level array, number, empty, missing, relative, trailing)
all -> exit=2 with parse-specific error message

# F8 — escaped quote in policy_id round-trips correctly
echo '{"policy_id":"abc\"def","allowed_executables":["/bin/echo"]}' > /tmp/eq.json
./bin/usernotify_exec_guard --policy /tmp/eq.json /bin/echo F8_TEST
  -> policy_id correctly recorded as "abc\"def" in audit JSON

# F5 — nested /proc/self/exe records child realpath, not supervisor
./bin/usernotify_exec_guard ... /usr/bin/python3 -c \
  'import os; os.execv("/proc/self/exe", ["/proc/self/exe", "--version"])'
  -> realpath:/usr/bin/python3.12 (the child's exe), Python 3.12.3 prints

# F5 — direct /proc/self/exe records supervisor binary because that IS the child's exe at decision time
./bin/usernotify_exec_guard ... /proc/self/exe --version
  -> realpath:/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard; BLOCK; exit=126
  (this is kernel-truthful — child has fork()'d but not yet execve'd)

# F6 — no sha256sum exec; AF_ALG instead
grep -nE 'sha256sum|/usr/bin/sha256' guard/usernotify_exec_guard.c
  -> (no hits)
strace -f -e trace=execve,socket,bind,accept4 ./bin/usernotify_exec_guard ... /usr/bin/git --version
  -> socket(AF_ALG, SOCK_SEQPACKET|SOCK_CLOEXEC, 0); bind(...salg_name="sha256"); accept4 — no execve to sha256sum
python3 -c '<AF_ALG vs hashlib.sha256 cross-check>'
  -> b94d27b9... matches sha256sum hello world

# F7 — argv truncation marker behavior
./bin/usernotify_exec_guard ... /bin/echo a b c d e f g h i j k l m n o p
  -> argv (8 entries), argv_truncated:true, argv_total_count:17
./bin/usernotify_exec_guard ... /bin/echo a b c
  -> argv (4 entries), argv_truncated:false, argv_total_count:4
./bin/usernotify_exec_guard ... /bin/echo "$(python3 -c 'print("X"*1024)')"
  -> argv[1] length 511, argv_truncated:true (per-arg cap), argv_total_count:2

# Sprint 1 invariants — all BLOCK
cp /bin/rm /tmp/git_audit_b
./bin/usernotify_exec_guard ... /tmp/git_audit_b --version
  -> BLOCK reason=blocked_executable_identity exit=126
ln -sf /bin/rm /tmp/python3_audit_b
./bin/usernotify_exec_guard ... /tmp/python3_audit_b --version
  -> BLOCK realpath=/usr/bin/rm exit=126
env PATH=/tmp:$PATH ./bin/usernotify_exec_guard ... /usr/bin/env python3_audit_b --version
  -> /usr/bin/env ALLOW; nested /tmp/python3_audit_b BLOCK

# Sprint 3 invariant — hardlink at non-allowed path
cp /bin/bash /tmp/bashcopy_audit_b && ln -f /tmp/bashcopy_audit_b /tmp/bashalias_audit_b
./bin/usernotify_exec_guard ... /tmp/bashalias_audit_b -c 'echo HI'
  -> BLOCK realpath=/tmp/bashalias_audit_b exit=126

# Carry-forward discipline — Sprint 4 memo opens with Carry-Forward Open Items
head -20 proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md
  -> "## Carry-Forward Open Items" header; F1-F8 enumerated; F4 explicitly Deferred

# Failed-run preservation
ls proofs/sprint4_runs/
  -> sprint4-20260430T232423Z (failed, pass=13 fail=1) AND sprint4-20260430T232441Z (passing, pass=14 fail=0) both kept

# Cleanup
rm -f /tmp/spoof_s4.policy.json /tmp/eq.json /tmp/array_root.json /tmp/num_allowed.json \
      /tmp/empty_allowed.json /tmp/no_allowed.json /tmp/rel_path.json /tmp/trailing.json \
      /tmp/unicode_policy.json /tmp/unicode_path.json /tmp/f1_forge_test.txt \
      /tmp/git_audit_b /tmp/python3_audit_b /tmp/bashcopy_audit_b /tmp/bashalias_audit_b
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint4_independent_review_b.md`
- Sprint 4 proof memo: `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`
- Sprint 4 command log: `proofs/SPRINT4_COMMAND_LOG_20260430.md`
- Sprint 4 replay harness: `scripts/replay_sprint4_audit_integrity.sh`
- Sprint 4 replay runs (this audit added one more):
  - `proofs/sprint4_runs/sprint4-20260430T232423Z/` (initial fail=1, harness expectation issue, preserved)
  - `proofs/sprint4_runs/sprint4-20260430T232441Z/` (Sprint 4 self-claim: pass=14 fail=0)
  - `proofs/sprint4_runs/sprint4-20260430T232950Z/` (this audit's first re-run)
  - `proofs/sprint4_runs/sprint4-20260430T233008Z/` (this audit's confirmation re-run, pass=14 fail=0)
- Sprint 2 replay run after Sprint 4: `proofs/sprint2_runs/sprint2-20260430T233011Z/` (pass=12 fail=0)
- Sprint 3 audit (predecessor): `proofs/AUDIT_20260430_sprint3_independent_review.md`
- Sprint 2 audits (predecessors): `proofs/AUDIT_20260430_sprint2_independent_review_a.md`, `proofs/AUDIT_20260430_sprint2_independent_review_b.md`
- Source: `guard/usernotify_exec_guard.c` (1258 lines, sha256 4d59cb35…)
- Binary: `bin/usernotify_exec_guard` (sha256 0bb35fd4…)
