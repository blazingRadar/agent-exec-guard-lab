# Sprint 4 — Independent Audit Review (Auditor A)

Date: 2026-04-30
Auditor: Auditor A (independent adversarial pass after Sprint 4 self-audit `SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`).
Posture: re-derive SHAs, re-run both replay harnesses, re-run each Sprint 2 reproduction (F1–F8) against the Sprint 4 binary, hunt for new bypass surfaces introduced by the fixes, check carry-forward discipline.
Source of record: live commands run on this host; SHAs re-derived; binary rebuilt and re-tested.
Parallel auditor: Auditor B running the same brief independently — no coordination.

---

## Audit Question

Did Sprint 4 (a) actually close F1, F2, F3, F5, F6, F7, F8 from the Sprint 2 carry-forward register, (b) honestly defer F4 with no quiet drop, (c) preserve Sprint 1, Sprint 2, Sprint 3 invariants, and (d) not introduce new bypass surfaces or audit-fidelity regressions?

## Verdict

**Sprint 4 substantially closes the audit-integrity findings it claims to close.** Six of the seven targeted findings (F1, F2, F3, F5, F6, F7, F8) reproduce as closed against the Sprint 4 binary using the exact reproduction commands from `AUDIT_20260430_sprint2_independent_review_a.md`. Sprint 2's 12-case identity replay still passes. The Landlock layer from Sprint 3 still holds. The `-fanalyzer` clean compile still holds. The Carry-Forward Open Items section is present in the memo. F4 is explicitly listed as deferred. The failed run at `sprint4-20260430T232423Z` is preserved with an honest harness-expectation explanation.

**Caveats — three small audit-fidelity gaps and one operator-side DoS that the Sprint 4 memo does not name:**

1. The custom hand-written JSON parser segfaults on deeply nested input (~100k brackets) due to unbounded recursion in `skip_json_value`. The policy file is operator-controlled and capped at 1MB by `slurp_file`, so this is operator-side DoS only — the supervised child cannot reach the parser. Discipline-correct fix is a fixed depth limit.
2. `argv_total_count` is capped at `MAX_ARGV_COUNT_SCAN = 256`. With a 300-arg child, the audit record reads `argv_total_count: 256, argv_truncated: true` — the recorded count is the scan cap, not the true argv length. The Sprint 4 memo claims `argv_total_count` is "the actual count from the child" — that is true for argv ≤ 256 and silently caps above.
3. The `child_stderr` event field passes the captured chunk through `json_escape`, which terminates at the first NUL byte. A supervised child can hide portions of its own stderr from the audit log by writing embedded NUL bytes. This is not forgery (the JSON wrapper is intact, the child cannot inject fake `exec_decision` records), but it is stealth — a child can suppress noise from its own audit trail.
4. The signal handler uses `snprintf` to a stack buffer plus `write(audit_fd, ...)` plus `_exit`. `snprintf` is not in the POSIX async-signal-safe list (signal-safety(7)). In practice it is safe here (no locale-aware specifiers, no allocation), but a discipline-correct version would format the message into a precomputed buffer at handler-install time or use only `write` of a fixed string. Minor — flag for Sprint 5+.
5. The JSON parser silently lossy-converts `"`-style escapes to `?` (line 499). A `policy_id` of `"id"suffix"` records as `"id?suffix"`. Audit-fidelity gap; not a bypass.
6. The `\u`-escape acceptance does not validate surrogate pairs and does not produce UTF-8 output. Same fidelity-only class as (5).

The honest one-line summary that survives this audit:

> "Sprint 4 closes the Sprint 2 audit-integrity findings F1, F2 (for catchable signals), F3 for the reproduced fail-open class, F5 for the reproduced `/proc/self/exe` case, F6 (no fork+exec to sha256sum), F7 (truncation marked), and F8 (subsumed by F3) against the Sprint 4 binary. F4 is explicitly carry-forward-deferred. The Sprint 2 12-case identity replay and Sprint 3 Landlock invariants still hold. SIGKILL is uncatchable and produces no audit record by Linux semantics. Audit fidelity has small residual gaps: `argv_total_count` saturates at 256, embedded NUL bytes truncate `child_stderr` data, `\u` escapes downconvert. The custom JSON parser has unbounded recursion that segfaults the supervisor on a ~100k-deep operator-supplied policy. The seccomp + Landlock decision invariant for the supervised child is not affected by these gaps."

Recommend: ship Sprint 4 as the audit-integrity baseline. Track the four small gaps above for Sprint 5 hardening before any external claim.

---

## What Verified Clean Independently

### Re-derived provenance

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
            scripts/replay_sprint4_audit_integrity.sh \
            scripts/replay_sprint2_identity.sh
4d59cb357cea8577057ebb861294f1623768e5d973e0bfd3be80e573792e3d07  guard/usernotify_exec_guard.c
0bb35fd4ab75dc28aa9e1e9334dbee3646b25bb1902117abfe94f12ad536b61c  bin/usernotify_exec_guard
afddc594ae1716aaed54725d4a346cdcfa351a54b881fb8a0b89719c86839d4a  scripts/replay_sprint4_audit_integrity.sh
a7ae211593b2241614bf0536130042ebe83eb70fba932bc364559386bb51b9d6  scripts/replay_sprint2_identity.sh

$ wc -l guard/usernotify_exec_guard.c
1258 guard/usernotify_exec_guard.c
```

All four SHAs match the values claimed in `SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`. Source grew from 793 (Sprint 3) to 1258 lines = +465 lines, consistent with the claimed additions (audit fd duplication, signal handler, custom JSON parser, child-context resolution, AF_ALG SHA256, argv truncation metadata, child_stderr framing).

### Re-run Sprint 4 audit-integrity replay

```
$ ./scripts/replay_sprint4_audit_integrity.sh
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
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260430T232950Z
```

14/14, matches Sprint 4 self-claim.

### Re-run Sprint 2 identity replay against Sprint 4 binary

```
$ ./scripts/replay_sprint2_identity.sh
PASS compile gcc clean
PASS allow_git ... PASS direct_block_rm ... PASS direct_block_rm_output ...
PASS bash_nested_block_rm ... PASS python_nested_block_rm ...
PASS copy_rename_bypass_blocked ... PASS copy_bypass_output ...
PASS symlink_bypass_blocked ... PASS env_path_bypass_blocked ...
PASS json_escape_hostile_path ... PASS execveat_blocked
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T232953Z
```

12/12, matches Sprint 2 baseline. Sprint 2 invariants preserved.

### Static analyzer compile

```
$ gcc -Wall -Wextra -fanalyzer -O2 -o /tmp/audit_a_analyzer guard/usernotify_exec_guard.c ; echo "exit=$?"
exit=0
```

`-fanalyzer` clean on a 1258-line C file is non-trivial. Discipline preserved.

### F1 — Audit forgery via shared stderr — CLOSED

Reproduction (verbatim from Sprint 2 A audit):

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_AUDITOR_A_S4\"}\n"); sys.stderr.flush()'
{"event":"exec_decision","timestamp":...,"raw_exe":"/usr/bin/python3","decision":"ALLOW","reason":"allowed_executable_identity",...}
{"event":"child_stderr","timestamp":...,"policy_id":"sprint2_identity_allowlist_v1","data":"\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_AUDITOR_A_S4\"}\n"}
{"event":"supervisor_exit",...}
```

The forged JSON is now wrapped as a `child_stderr` event with the entire forged blob escaped inside a `data` string field. A downstream JSON parser sees three top-level events: a real `exec_decision`, a `child_stderr` whose data is opaque text, and a `supervisor_exit`. The forged record is no longer indistinguishable from a real supervisor decision.

Implementation verification:

- Child fd inspection (`os.readlink("/proc/self/fd/N")`):
  - fd 0 → `/dev/null`
  - fd 1 → terminal/output file
  - fd 2 → `pipe:[…]` (the supervisor-owned read end)
  - fd 3+ → not present
- Source: `audit_fd = fcntl(STDERR_FILENO, F_DUPFD_CLOEXEC, 3); audit_out = fdopen(audit_fd, "a");` (lines 1194–1198).
- The child closes `audit_fd` explicitly before `execvp` (line 1231) and the dup is `F_DUPFD_CLOEXEC`, so even without the explicit close it would not survive `execve`. Belt-and-braces.
- The child-stderr pipe read end (`child_stderr[0]`) is also not exposed to the child (the child closed it on line 1226 and execve's the pipe write end as fd 2).

Conclusion: the child cannot guess the audit fd number and cannot inherit it. Supervisor audit JSON cannot be forged via stderr writes. F1 closed for the reproduced class.

### F2 — Supervisor killable with no final record — CLOSED for catchable signals

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import os, signal; os.kill(os.getppid(), signal.SIGTERM)'
{"event":"exec_decision",...}
{"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGTERM"}
exit=143

$ ... signal.SIGINT
{"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGINT"}
exit=130

$ ... signal.SIGHUP
{"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGHUP"}
exit=129

$ ... signal.SIGKILL
(no supervisor_exit JSON; SIGKILL uncatchable)
exit=137
```

SIGTERM/INT/HUP all emit `supervisor_exit{reason:killed_by_signal,signal:<name>}` before `_exit(128+signo)`. SIGKILL is by Linux semantics not catchable; the supervisor dies silently. The Sprint 4 memo does not explicitly say SIGKILL is uncatchable; it says only "for SIGTERM/INT/HUP." That is honest by omission but I'd recommend an explicit one-liner in the carry-forward register: "SIGKILL/SIGSTOP-then-SIGKILL still produces no record by kernel semantics; not closable in user-space." Minor disclosure improvement, not a finding.

Signal handler safety:

- `fatal_signal_handler` (lines 95–113) calls `snprintf` (stack buffer), `write` (raw fd), `_exit`. `write` and `_exit` are POSIX async-signal-safe; `snprintf` is not in the strict POSIX list (signal-safety(7)) but is safe in practice for this use (no locale-aware specifiers, no `%s` on user strings, no allocation). Discipline-correct alternative: format the message at handler-install time. Flag for Sprint 5.
- The handler does not take any FILE-level locks — it bypasses `audit_out` and writes directly to `audit_fd`. Correct.
- The handler writes a single complete JSON line ending in `\n`. If a partial JSON line was buffered in `audit_out` (line-buffered, so unlikely), it would be lost. In practice all writes are full lines.
- The signal mask in the handler is empty (`sigemptyset(&sa.sa_mask)`), so the same signal is masked by default during its own handler (POSIX `SA_NODEFER` is unset). Multiple SIGTERMs cannot re-enter the handler; the handler reaches `_exit` and is gone.
- A SIGTERM arriving mid-`ioctl(SECCOMP_IOCTL_NOTIF_RECV)` interrupts the syscall, the handler runs, the handler `_exit`s. The supervised child loses its supervisor; the child's seccomp filter remains installed in-kernel and prevents new exec. This is the correct architectural behavior.

F2 closed for catchable signals. SIGKILL gap is architectural and properly framed by the memo.

### F3 — Policy parser fail-open — CLOSED for reproduced and adjacent classes

Verbatim Sprint 2 A repro:

```
$ cat > /tmp/audit_a_spoof.json <<'JSON'
{"policy_id":"spoof","allowed_executables":"should_be_array","extra":["/bin/echo"],"more_paths":["/bin/rm"]}
JSON
$ ./bin/usernotify_exec_guard --policy /tmp/audit_a_spoof.json /bin/echo SPOOF_TEST
policy JSON parse error: allowed_executables must be array
exit=2
```

Adjacent hostile inputs all also fail closed:

| Input | Result |
|---|---|
| `"allowed_executables": 42` (number) | parse error: must be array, exit 2 |
| `"allowed_executables": ["bin/echo"]` (relative) | parse error: must be absolute, exit 2 |
| `"allowed_executables": ["/bin/echo", 42, "/bin/cat"]` (mixed) | parse error: entries must be strings, exit 2 |
| `"allowed_executables": []` (empty) | "policy has no allowed executable paths", exit 2 |
| `"policy_id": "x"` (no `allowed_executables` key at all) | "policy has no allowed executable paths", exit 2 |
| Trailing garbage after root `}` | parse error: trailing data, exit 2 |
| `"unknown": {"deeply": {"nested": [1,{"x":null}]}}` next to a valid `allowed_executables` | parses cleanly via `skip_json_value` recursion, ALLOWs the valid entry |
| Path that does not resolve | "policy path does not resolve: ...", exit 2 |
| `policy_id` containing `\"` (F8) | recorded faithfully in audit JSON; verified by `json.loads` round-trip |

JSON library: hand-written. Confirmed via `pkg-config --exists jansson` (no), `pkg-config --exists json-c` (no), and reading lines 442–755 of `usernotify_exec_guard.c`. The parser is single-pass, recursive, and approximately RFC 8259 compliant for the policy schema. Not a general-purpose library; intentionally narrow.

Static-analyzer-clean and locally consistent. F3 closed for the reproduced class and adjacent classes.

See "New findings" below for a parser-stack DoS observation that is outside the F3 closure scope.

### F5 — `/proc/self/exe` resolves in supervisor namespace — CLOSED for reproduced case

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import os; os.execv("/proc/self/exe", ["/proc/self/exe", "--version"])'
{"event":"exec_decision",...,"raw_exe":"/usr/bin/python3","realpath":"/usr/bin/python3.12",...}
{"event":"exec_decision",...,"raw_exe":"/proc/self/exe","realpath":"/usr/bin/python3.12",...}
Python 3.12.3
{"event":"supervisor_exit",...}
exit=0
```

The audit log now records `realpath: /usr/bin/python3.12` (the child's actual exe), not the supervisor's binary. Resolution mechanism (lines 769–794): when `raw` starts with `/proc/self/`, the supervisor rewrites to `/proc/<child_pid>/...`; absolute paths are resolved through `/proc/<child_pid>/root/...` (anchors them in the child's mount namespace). Relative paths use the child's cwd as read from `/proc/<child_pid>/cwd`.

Race-condition analysis: the supervisor reads `/proc/<child_pid>/exe`/`root` at decision time. Could the child fork-and-double-exec to swap its own identity between the supervisor's read and the kernel's exec? Two protections:

1. The seccomp `notif_id` is bound to the specific stopped exec syscall in the specific child task. `notification_id_valid()` is rechecked after `decide_exec` (line 1150). If the child task is gone, the decision is forced to BLOCK with reason `notification_id_invalid`.
2. `/proc/<child_pid>/exe` is anchored to the kernel's view of the process exe — the child cannot "swap" its own exe link arbitrarily.

A double-fork pattern (child A forks child B; A is what the supervisor reads; B does the actual exec) does not apply here because the seccomp filter is inherited and only B's exec triggers the user-notif; the supervisor reads `/proc/<B_pid>/...`, which is correct.

F5 closed for the reproduced nested-child case.

### F6 — `file_sha256` fork+execs `sha256sum` — CLOSED

```
$ grep -n "sha256sum" guard/usernotify_exec_guard.c
(no match)

$ grep -nE "AF_ALG|salg|sockaddr_alg" guard/usernotify_exec_guard.c
325:    int tfm_fd = socket(AF_ALG, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
331:    struct sockaddr_alg sa;
333:    sa.salg_family = AF_ALG;
334:    snprintf((char *)sa.salg_type, sizeof(sa.salg_type), "hash");
335:    snprintf((char *)sa.salg_name, sizeof(sa.salg_name), "sha256");

$ strings bin/usernotify_exec_guard | grep -E "sha256sum|/usr/bin/sha"
(no match)
```

No fork+exec. Linux AF_ALG `hash/sha256` is the path.

AF_ALG socket lifecycle (lines 319–385): opened **per call** (per policy load entry, per `decide_exec`). Not leaked to the child. `O_CLOEXEC` set via `SOCK_CLOEXEC` and `accept4(SOCK_CLOEXEC)`. Closed before return on every code path including failure. No fd leak.

Failure semantics: if AF_ALG is unavailable (kernel module not loaded, EAFNOSUPPORT on `socket`, EAFNOSUPPORT on `bind`), `file_sha256` returns false. Both call sites (`add_policy_path` line 438, `decide_exec` line 1002) ignore the return value. The decision uses dev/ino identity, not SHA256, so AF_ALG failure does **not** change the security posture — it just leaves the audit log's `sha256` field as the prior initialized value (`unavailable` for decisions, empty for policy entries). This is correct fail-soft for an audit-only field. The Sprint 4 memo could explicitly state "policy decision is dev/ino-based; SHA256 is for audit only and degrades to `unavailable` if AF_ALG is missing." Minor disclosure improvement.

Perf: per-call AF_ALG open is a few syscalls (socket, bind, accept4, read/write loop, close). Comparable to or faster than fork+exec to /usr/bin/sha256sum. No measured regression.

F6 closed.

### F7 — argv silent truncation — CLOSED for primary case, fidelity-capped for argv > 256

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /bin/echo a b c d e f g h i j k l
"argv":["/bin/echo","a","b","c","d","e","f","g"]
"argv_truncated":true
"argv_total_count":13

$ /bin/echo with 7 args (8 total including argv[0]):
"argv":["/bin/echo","a","b","c","d","e","f","g"]
"argv_truncated":false
"argv_total_count":8

$ /bin/echo with 1 user-arg (2 total):
"argv_truncated":false
"argv_total_count":2

$ /bin/echo with a 1000-byte single arg:
"argv_truncated":true
"argv_total_count":2

$ /bin/echo with 300 args:
"argv_truncated":true
"argv_total_count":256   ← capped at MAX_ARGV_COUNT_SCAN
```

Truncation is now marked. `argv_truncated=true` fires on (a) more than `MAX_ARGV_CAPTURE = 8` args, (b) any single arg longer than 512 bytes, (c) JSON buffer overflow into `argv_json`. Reasonable.

Escape correctness verified for `"`, `\`, embedded newline:

```
$ /bin/echo 'a"b' 'c\d' $'e\nf'
"argv":["/bin/echo","a\"b","c\\d","e\nf"]
$ python3 -c 'import json,sys; obj=json.loads(sys.stdin.read()); print(obj["argv"])'
['/bin/echo', 'a"b', 'c\\d', 'e\nf']
```

Round-trips through `json.loads`.

**Audit-fidelity gap**: `argv_total_count` is the count up to `MAX_ARGV_COUNT_SCAN = 256`. With 300 actual args, the recorded count says 256. The audit consumer cannot distinguish "9 args" (true count = 9, truncated = true) from "300 args" (true count = 300, recorded = 256, truncated = true). Sprint 4 memo phrases this as "the actual count from the child"; that is true for argv ≤ 256 and capped above. Minor honesty tightening: rename to `argv_scanned_count` or document the 256-cap explicitly.

F7 closed for the reproduced case; recommend tightening the field semantics doc.

### F8 — `policy_id` with escaped quote — CLOSED (subsumed by F3)

```
$ cat > /tmp/audit_a_f8.json <<'JSON'
{"policy_id":"with_\"escaped\"_quote","allowed_executables":["/bin/echo"]}
JSON
$ ./bin/usernotify_exec_guard --policy /tmp/audit_a_f8.json /bin/echo F8_TEST
{...,"policy_id":"with_\"escaped\"_quote",...}
```

Round-trip via `json.loads` produces `'with_"escaped"_quote'`. The new parser in `parse_json_string` correctly handles `\"` `\\` `\b` `\f` `\n` `\r` `\t` `\u????`. F8 closed.

### Sprint 1 invariants

```
$ cp /bin/rm /tmp/audit_a_git
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/audit_a_git --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity",...}

$ ln -sf /bin/rm /tmp/audit_a_link
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/audit_a_link --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity",...}
```

Basename copy: BLOCK. Symlink: BLOCK. PATH-hijack: covered by Sprint 2 replay (env_path_bypass_blocked PASS). Sprint 1 invariants preserved.

### Sprint 3 invariants

```
$ cp /bin/bash /tmp/audit_a_bashcopy && ln /tmp/audit_a_bashcopy /tmp/audit_a_bashalias
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/audit_a_bashalias -c 'echo hi'
{...,"decision":"BLOCK","reason":"blocked_executable_identity",...}
```

Hardlink-at-non-allowed-path: BLOCK. Landlock execute underlay (lines 915–959) still installed in child before execve. The Landlock loader anchors at lines 941–945 are unchanged from Sprint 3.

Sprint 3 invariants preserved.

---

## New Findings Introduced By (or Adjacent To) Sprint 4 Fixes

### N1 (LOW, operator-side DoS): JSON parser unbounded recursion → SIGSEGV on deeply nested policy

```
$ python3 -c '
n = 100000
print("{\"policy_id\":\"deep\",\"unknown\":" + "["*n + "1" + "]"*n + ",\"allowed_executables\":[\"/bin/echo\"]}")' > /tmp/audit_a_deep.json

$ ls -la /tmp/audit_a_deep.json
-rw-rw-r-- 1 ... 200069 ...   # 200KB, well under the 1MB slurp_file cap

$ ./bin/usernotify_exec_guard --policy /tmp/audit_a_deep.json /bin/echo DEEP
Segmentation fault (core dumped)
exit=139
```

Cause: `skip_json_value` → `skip_json_array` → `skip_json_value` is unbounded recursion. With ~100k nesting on an 8MB stack, the stack overflows. `slurp_file` caps the policy file at 1MB (line 397), so a million-deep nest does not fit, but 100k–500k fits and segfaults reliably.

Severity: low. The supervised child cannot reach this code path — the parser runs at policy load before any child is forked. Only the operator (who controls the policy file) can trigger it. The discipline-correct fix is a fixed depth limit (e.g., 64) in `skip_json_value`/`skip_json_object`/`skip_json_array`, returning a parse error past the limit. Cheap to add.

Why mention: the Sprint 4 memo says "strict in-process JSON parser for this policy schema" and "escaped strings are handled instead of `strstr`/`strchr` field walking." Both are true. The honest framing should add "with a recursion depth that should be bounded for robustness." Sprint 5 hardening item.

### N2 (audit-fidelity, low severity): `argv_total_count` saturates at 256

Already documented under F7 above. Audit consumer sees `argv_total_count: 256, argv_truncated: true` for any argv length ≥ 256. Cannot distinguish 256 from 10000. Sprint 4 memo overstates slightly when it implies `argv_total_count` is a true total. Recommend renaming to `argv_scanned_count` or documenting the cap.

### N3 (audit-fidelity, low severity): `child_stderr` data field NUL-truncates

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stderr.buffer.write(b"VISIBLE\x00HIDDEN\nMORE\n"); sys.stderr.flush()'
{"event":"child_stderr",...,"data":"VISIBLE"}
```

`write_child_stderr_json` (line 1064) copies `len` bytes into a `tmp[1025]` buffer, NUL-terminates at `n`, then calls `json_escape(out, tmp)` which iterates until the first NUL (`*p` loop in `json_escape`). Bytes after the first embedded NUL are dropped from the audit. Not forgery (the JSON wrapper survives, no fake `exec_decision` is injected), but allows a child to suppress portions of its own stderr from the audit trail. The child cannot inject *new* events through this — it can only erase its own noise.

Fix: pass `len` through to `json_escape`, iterate over `len` bytes instead of stopping at NUL, and emit ` ` for embedded NULs.

### N4 (discipline / disclosure, very low): SIGKILL silence not explicitly named in the carry-forward register

The Sprint 4 memo's F2 row says "Closed for SIGTERM/INT/HUP." That implicitly acknowledges SIGKILL is not closed, but a downstream reader who skims the table may miss it. Recommend an explicit one-liner: "SIGKILL is uncatchable by Linux semantics; supervisor death from SIGKILL leaves no audit record, no user-space fix exists. Mitigation: the child's seccomp filter persists in-kernel after supervisor death, so no new exec is possible without a supervisor."

### N5 (discipline / async-signal-safety, very low): signal handler uses `snprintf`

`fatal_signal_handler` (lines 95–113) uses `snprintf` to a stack buffer. Not in the strict POSIX async-signal-safe list. In practice safe here (no `%s` on user data, no locale-aware formatting, no allocation), but the strictly correct alternative is to format the message at handler-install time and `write()` a precomputed string in the handler. Discipline tightening for Sprint 5.

### N6 (audit-fidelity, very low): `\u????` escapes downconvert to `?`

`parse_json_string` (line 499) accepts `\uXXXX` syntactically but stores `'?'`. A `policy_id` containing `"` records as `id?suffix` in the audit log. Not a bypass — JSON parsing still works — but a small fidelity loss. Sprint 5 cleanup item if the parser stays hand-written.

---

## Carry-Forward / Discipline Observations

### Carry-forward Open Items section: PRESENT and CORRECT

`SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md` lines 7–18 contains the recommended `## Carry-Forward Open Items` section as a table. F1, F2, F3, F4, F5, F6, F7, F8 are each listed with current status. F4 is explicitly listed as "Deferred."

This is the discipline recommendation from `AUDIT_20260430_sprint3_independent_review.md` lines 263–267. **Adopted.** Credit.

### F4 deferral honest

F4 is named in the carry-forward register, marked "Deferred," with the framing "Sprint 3 Landlock reduces practical non-policy executable execution, but fd-stable execution remains Sprint 5+ architecture work." That is accurate. Landlock does materially reduce the practical exploitability of an `F_CONT` post-decision swap, because a swap to a non-policy path is denied at exec time even if seccomp said `CONTINUE`. A swap to another policy-allowed path (e.g., `/usr/bin/git` → `/usr/bin/python3` mid-syscall) is still possible by Landlock semantics; the architectural fix is `SECCOMP_IOCTL_NOTIF_ADDFD` per the Sprint 3 fix-path analyses. The deferral framing is honest.

### Failed run preservation: HONEST

```
$ ls /home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/
sprint4-20260430T232423Z   sprint4-20260430T232441Z

$ cat .../sprint4-20260430T232423Z/replay_summary.txt | tail -5
PASS f7_argv_truncation_marked exit=0
PASS f7_argv_truncation_fields argv truncation metadata emitted
pass=13 fail=1
```

The 13/14 first run is preserved. `SPRINT4_COMMAND_LOG_20260430.md` lines 41–50 explains: the harness initially expected `/usr/bin/python3` realpath, but the host's `realpath /usr/bin/python3` is `/usr/bin/python3.12`, so the harness was corrected. That is a harness expectation issue, not a guard regression. The fix correctly compares against `realpath /usr/bin/python3` (line 136 of the replay script). Honest framing.

### Replay script integrity

`replay_sprint2_identity.sh` SHA `a7ae2115…` is unchanged across Sprint 2/3/4. The Sprint 2 baseline is replayed against the new binary, not against a regenerated reference set. Discipline preserved.

### `/tmp` cleanup

Sprint 4 self-audit run materials live under `proofs/sprint4_runs/.../work/` (not `/tmp/`). My audit's `/tmp/audit_a_*.json` and `/tmp/audit_a_*` artifacts have been removed (see Commands section).

---

## F4 Residual Posture

F4's framing in Sprint 4 memo: "`SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU. Deferred. Sprint 3 Landlock reduces practical non-policy executable execution, but fd-stable execution remains Sprint 5+ architecture work."

Audit verdict on this framing: **accurate.**

What F4 actually is: when the supervisor returns `SECCOMP_USER_NOTIF_FLAG_CONTINUE`, the kernel re-runs the original `execve(path, argv, envp)` with the original arguments. Between decision and re-run, the child can swap the file at `path` (or follow a swapped symlink) and exec a different inode. Landlock blocks this if the new inode is at a non-policy path. Landlock does not block this if the new inode is at a different policy-allowed path (e.g., the operator allowed `/usr/bin/git` and `/usr/bin/python3`, the child swaps `/usr/bin/git` to a script that re-resolves to `/usr/bin/python3` at exec time). The architectural fix is `SECCOMP_IOCTL_NOTIF_ADDFD` to install a verified fd in the child and rewrite the syscall to `execveat(fd, "", argv, envp, AT_EMPTY_PATH)`. Deferred to Sprint 5+.

This is correctly framed.

---

## Sprint 5 Prerequisites (audit-derived)

In rough priority:

1. **F4 architectural fix.** `SECCOMP_IOCTL_NOTIF_ADDFD` + `execveat(AT_EMPTY_PATH)` to eliminate the `F_CONT` TOCTOU. The Sprint 3 fix-path analyses (`SPRINT3_FIX_PATH_ANALYSIS_A_20260430.md` Φ_B section) named this. Highest-value remaining hardening before any external claim.
2. **N1 fix.** Add a fixed recursion depth limit (e.g., 64) to `skip_json_value`/`skip_json_object`/`skip_json_array`. Cheap; closes the operator-side parser DoS.
3. **N3 fix.** Pass `len` through to `json_escape` for `child_stderr` data; emit ` ` for embedded NULs. Cheap; closes the child-stderr stealth gap.
4. **N2 / F7 honesty tightening.** Either expand `argv_total_count` to scan beyond 256 (e.g., 4096), or rename to `argv_scanned_count` and document the cap explicitly. Cheap.
5. **N5 discipline tighten.** Move signal-handler message formatting to handler-install time; use only `write` of a fixed string in the handler. Cheap.
6. **N4 disclosure.** Add explicit SIGKILL line to the F2 row of the carry-forward register. Free.
7. **Docker / OpenHands integration probe.** With audit-integrity now in shape, the next blocker is integration proof. Out of scope for this audit.
8. **Optional**: Landlock anchor schema in policy (operator-controlled exact-file vs path-beneath rules). Was named as Sprint 4 prerequisite (8) in Sprint 3 audit; not landed in Sprint 4 but not load-bearing for audit integrity.

---

## Honest Claim Tightening

Sprint 4's "Claim Now Allowed" (lines 105–107 of self-audit memo):

> "A local seccomp user-notify execution guard can preserve Sprint 2 identity decisions, preserve Sprint 3 Landlock execute-underlay behavior, and emit audit records on a supervisor-owned stream that the supervised child cannot forge by writing JSON to stderr. It records signal-kill termination, rejects the reproduced malformed-policy fail-open case, resolves `/proc/self/exe` from the child process context for the reproduced nested case, computes SHA256 in-process, and marks argv truncation."

Verdict on this claim: **accurate as written.** It is carefully scoped ("for the reproduced … case", "signal-kill termination" without claiming SIGKILL, "marks argv truncation" without claiming exact total count). I would only add one short clause for fairness:

> "… and marks argv truncation. The audit pipeline still has small fidelity caps (`argv_total_count` saturates at 256; embedded-NUL bytes truncate `child_stderr` data) and the operator-side custom JSON parser is not depth-bounded; these are tracked for Sprint 5 hardening and do not weaken the seccomp + Landlock decision invariant for the supervised child."

That tightening keeps the claim load-bearing while pre-empting the small new-finding surface that this audit produced.

---

## Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

# Re-derive provenance
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
          scripts/replay_sprint4_audit_integrity.sh scripts/replay_sprint2_identity.sh
  -> 4d59cb35…  guard/usernotify_exec_guard.c
  -> 0bb35fd4…  bin/usernotify_exec_guard
  -> afddc594…  scripts/replay_sprint4_audit_integrity.sh
  -> a7ae2115…  scripts/replay_sprint2_identity.sh
wc -l guard/usernotify_exec_guard.c
  -> 1258 (was 793 in Sprint 3, +465 lines)

# Replay reruns
./scripts/replay_sprint4_audit_integrity.sh
  -> pass=14 fail=0  run_root=…/sprint4_runs/sprint4-20260430T232950Z
./scripts/replay_sprint2_identity.sh
  -> pass=12 fail=0  run_root=…/sprint2_runs/sprint2-20260430T232953Z

# Static analyzer
gcc -Wall -Wextra -fanalyzer -O2 -o /tmp/audit_a_analyzer guard/usernotify_exec_guard.c
  -> exit=0 (clean)
rm -f /tmp/audit_a_analyzer

# F1 forgery via stderr
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_AUDITOR_A_S4\"}\n")'
  -> Forged JSON wrapped as child_stderr.data; no top-level forged exec_decision

# F1 child fd inspection
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /bin/bash -c 'ls -la /proc/self/fd/'
  -> fd0=/dev/null  fd1=output_file  fd2=pipe:[…]  fd3=/proc/<pid>/fd (from readdir)

# F1 forgery via stdout (different fd)
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stdout.write("...")'
  -> stdout is not the audit stream; forgery has no path to audit JSON

# F2 catchable signals
... SIGTERM -> {"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGTERM"} exit=143
... SIGINT  -> {... "signal":"SIGINT"}  exit=130
... SIGHUP  -> {... "signal":"SIGHUP"}  exit=129
... SIGKILL -> (no JSON) exit=137  [uncatchable; expected]

# F3 hostile policies
... allowed_executables="should_be_array"        -> parse error: must be array, exit 2
... allowed_executables=42                       -> parse error: must be array, exit 2
... allowed_executables=["bin/echo"]             -> parse error: must be absolute, exit 2
... allowed_executables=["/bin/echo",42,"/bin/cat"] -> parse error: must be strings, exit 2
... allowed_executables=[]                       -> "no allowed executable paths", exit 2
... missing allowed_executables key              -> "no allowed executable paths", exit 2
... trailing data after }                        -> parse error: trailing data, exit 2
... nested unknown values + valid allowed_executables -> ALLOWs valid entry (skip_json_value handles depth)

# F5 /proc/self/exe
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import os; os.execv("/proc/self/exe", ["/proc/self/exe","--version"])'
  -> raw_exe=/proc/self/exe  realpath=/usr/bin/python3.12  ALLOW

# F6 verify no sha256sum, AF_ALG path
grep -n sha256sum guard/usernotify_exec_guard.c           -> (no match)
grep -nE "AF_ALG|salg" guard/usernotify_exec_guard.c       -> AF_ALG/sockaddr_alg/hash/sha256
strings bin/usernotify_exec_guard | grep sha256sum         -> (no match)

# F7 argv truncation
... 13 user-args     -> argv[8 captured] argv_truncated=true argv_total_count=13
... 7  user-args     -> argv[8 captured] argv_truncated=false argv_total_count=8
... 1000-byte arg    -> argv_truncated=true argv_total_count=2
... 300 user-args    -> argv_truncated=true argv_total_count=256  ← cap
... 'a"b' 'c\d' 'e\nf' -> argv:["/bin/echo","a\"b","c\\d","e\nf"]  (round-trips through json.loads)

# F8 escaped quote in policy_id
{"policy_id":"with_\"escaped\"_quote",...}
  -> audit JSON: "policy_id":"with_\"escaped\"_quote"  (parses to with_"escaped"_quote)

# Sprint 1 / Sprint 3 invariants
cp /bin/rm /tmp/audit_a_git
./bin/usernotify_exec_guard ... /tmp/audit_a_git --version    -> BLOCK
ln -sf /bin/rm /tmp/audit_a_link
./bin/usernotify_exec_guard ... /tmp/audit_a_link --version   -> BLOCK
cp /bin/bash /tmp/audit_a_bashcopy && ln /tmp/audit_a_bashcopy /tmp/audit_a_bashalias
./bin/usernotify_exec_guard ... /tmp/audit_a_bashalias -c 'echo hi' -> BLOCK

# N1 parser DoS
python3 -c 'n=100000; print("{\"policy_id\":\"deep\",\"unknown\":" + "["*n + "1" + "]"*n + ",\"allowed_executables\":[\"/bin/echo\"]}")' > /tmp/audit_a_deep.json
./bin/usernotify_exec_guard --policy /tmp/audit_a_deep.json /bin/echo DEEP
  -> Segmentation fault (core dumped), exit=139

# N3 child_stderr NUL truncation
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stderr.buffer.write(b"VISIBLE\x00HIDDEN\nMORE\n")'
  -> child_stderr data = "VISIBLE"  (HIDDEN/MORE dropped)

# Cleanup
rm -f /tmp/audit_a_git /tmp/audit_a_link /tmp/audit_a_bashcopy /tmp/audit_a_bashalias \
      /tmp/audit_a_*.json /tmp/audit_a_argv.txt /tmp/audit_a_fds.txt /tmp/audit_a_stderr.txt \
      /tmp/audit_a_analyzer
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint4_independent_review_a.md`
- Sprint 4 self-audit: `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`
- Sprint 4 command log: `proofs/SPRINT4_COMMAND_LOG_20260430.md`
- Sprint 4 replay (this audit's run): `proofs/sprint4_runs/sprint4-20260430T232950Z/`
- Sprint 4 self-audit's replay: `proofs/sprint4_runs/sprint4-20260430T232441Z/`
- Sprint 4 preserved failed run: `proofs/sprint4_runs/sprint4-20260430T232423Z/`
- Sprint 2 replay (this audit's run): `proofs/sprint2_runs/sprint2-20260430T232953Z/`
- Sprint 3 audit: `proofs/AUDIT_20260430_sprint3_independent_review.md`
- Sprint 2 audits: `proofs/AUDIT_20260430_sprint2_independent_review_{a,b}.md`
- Sprint 1 audit: `proofs/AUDIT_20260430_sprint1_independent_review.md`
- Source: `guard/usernotify_exec_guard.c` (1258 lines, sha256 4d59cb35…)
- Binary: `bin/usernotify_exec_guard` (sha256 0bb35fd4…)
