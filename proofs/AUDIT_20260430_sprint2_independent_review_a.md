# Sprint 2 — Independent Audit Review (Auditor A)

Date: 2026-04-30
Auditor: independent third pass after Sprint 2 self-audit (`SPRINT2_AUDIT_20260430.md`).
Posture: adversarial review, with live re-derivation, conducted in parallel with Auditor B (no coordination).
Source of record: live commands run on this machine; SHAs re-derived; bypass tests reproduced; new bypass classes probed.

---

## Audit Question

Did Sprint 2 (a) actually close the Sprint 1 basename/symlink/PATH-hijack bypasses, (b) deliver the headline architecture and audit changes claimed, and (c) introduce any new bypass or audit-integrity classes the candidate missed? And what should be tightened before Sprint 3 / before Docker?

## Verdict

**Sprint 2 closes the three Sprint 1 bypasses on this machine. The realpath+dev+ino identity check is real and works. The discipline shape is honest and the failed harness run is preserved.** But the headline overstates trust-boundary integrity in two ways the candidate did not name:

1. The supervised child can **forge audit records** (and corrupt the JSON stream) because the supervisor and child share fd 2; this is a live, demonstrable audit-trail integrity defect.
2. The supervised child can **kill the supervisor** with `kill(getppid(), SIGTERM)`, which terminates the audit stream silently (no `supervisor_exit` line) — a denial-of-audit, not a bypass for execve, but it disproves "supervisor outside the trap boundary" as a security claim.

The honest one-line summary should be:

> "Sprint 2 replaces basename matching with realpath+dev+ino identity, externalizes policy to JSON, enriches audit records, and moves the seccomp filter into the child via a Unix-socket fd handoff. The basename/symlink/PATH-hijack bypasses verified in Sprint 1 are now blocked. The supervisor remains in the same UID/PID-namespace as the child, the audit stream shares fd 2 with the child, and the ALLOW path still uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE`; therefore the audit log can be forged or corrupted by the child, the supervisor can be killed by the child, and the documented `CONTINUE` TOCTOU window remains. Sprint 2 is a stronger mechanism proof, not a security boundary."

---

## What Verified Clean Independently

Re-derived from disk just now:

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
58b8409de0c53d4be2e742cac11877902b1c6249c9e8a4a06e7b053314a4aae2  guard/usernotify_exec_guard.c
40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415  bin/usernotify_exec_guard

$ wc -l guard/usernotify_exec_guard.c
672 guard/usernotify_exec_guard.c
```

Both SHAs match the values claimed in `SPRINT2_AUDIT_20260430.md` and `SPRINT2_COMMAND_LOG_20260430.md`.

Re-running the replay script just now produced:

```
PASS compile gcc clean
PASS allow_git ... PASS direct_block_rm ... PASS bash_nested_block_rm ...
PASS python_nested_block_rm ... PASS copy_rename_bypass_blocked ...
PASS symlink_bypass_blocked ... PASS env_path_bypass_blocked ...
PASS json_escape_hostile_path ... PASS execveat_blocked
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T221125Z
```

Sprint 1 bypasses re-run live against the Sprint 2 binary:

- `cp /bin/rm /tmp/git` then `guard /tmp/git --version` → BLOCK with `reason=blocked_executable_identity`, `realpath=/tmp/git`, `sha256=8e3faaa5…` (the rm sha). Exit 126. **Closed.**
- `ln -sf /bin/rm /tmp/python3` then `guard /tmp/python3 --version` → BLOCK with `realpath=/usr/bin/rm` (symlink resolved through), `sha256=8e3faaa5…`. Exit 126. **Closed.**
- `mkdir /tmp/hi && cp /bin/rm /tmp/hi/git && PATH=/tmp/hi:$PATH guard git --version` → BLOCK with `raw_exe=/tmp/hi/git`, `realpath=/tmp/hi/git`, `sha256=8e3faaa5…`. Exit 126. **Closed.**

Headline JSON fields verified present in both ALLOW and BLOCK records by parsing live output:
`event, timestamp, policy_id, pid, syscall, notif_id, decision, reason, raw_exe, realpath, cwd, dev, ino, sha256, argv` — all present in `exec_decision` records. `supervisor_exit` records carry `event, timestamp, policy_id, child_exit`. No claimed field missing.

Architecture changes verified by reading `guard/usernotify_exec_guard.c` line-by-line:
- Filter installed only in the child via `install_exec_listener` after `fork()` (lines 651–657) and before `execvp`.
- Listener fd handed back to the parent via Unix `socketpair` and `SCM_RIGHTS` (lines 641–670).
- `SECCOMP_IOCTL_NOTIF_ID_VALID` checked before SEND (lines 597–600). On failure, the decision is rewritten to BLOCK with `reason=notification_id_invalid`. This matches the claim.
- `execveat` is recognised by the BPF filter and notified, then the userspace `decide_exec` shortcuts to BLOCK with `reason=execveat_not_supported_in_sprint2` (lines 459–465).
- ALLOW path still uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE` (line 604). Documented limitation; matches the candidate's own caveat.
- `PR_SET_NO_NEW_PRIVS` set before filter install (line 86). Preserved from Sprint 1.

Failed harness run preserved at `proofs/sprint2_runs/sprint2-20260430T220518Z`:
- `replay_summary.txt` shows `pass=10 fail=2` with the env-path case failing because the harness leaked PATH into its own JSON-validation step. The case directories, command files, and stderr are intact. **Honest preservation.**

Policy file fail-closed behaviour verified by exhaustive edge cases (missing file, empty file, no `allowed_executables` key, empty array, non-existent path inside, garbled JSON, truncated JSON): every case exits with status 2 and prints a specific error. **No fail-open path observed.**

JSON escaping of argv and paths containing `"`, `\`, `\n`, `\r`, `\t`, control bytes is correct (verified by feeding hostile argv and parsing each output line with `json.loads`).

Discipline shape is good:
- Pre-registered scope with explicit "claims still not allowed" list.
- Failed run preserved instead of overwritten.
- Per-case directories with `command.txt`, `exit_code.txt`, `stdout.txt`, `stderr.txt`, and `json_check.*`.
- SHA256 anchoring of source and binary in every passing run.
- TOCTOU residual posture explicitly named, not buried.

---

## Critical Finding 1 — Audit log can be forged by the supervised child (severity: HIGH)

Live demonstration, just now:

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import sys
sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_BY_CHILD\"}\n")
sys.stderr.flush()
' 2>/tmp/forge.stderr
```

Audit stream contents:

```
{"event":"exec_decision",...,"raw_exe":"/usr/bin/python3",...,"decision":"ALLOW","reason":"allowed_executable_identity",...}

{"event":"exec_decision","decision":"ALLOW","raw_exe":"/bin/rm","reason":"FORGED_BY_CHILD"}
{"event":"supervisor_exit",...}
```

Parsed by `python3 -c "import json,sys; …"`:

```
exec_decision ALLOW /usr/bin/python3 allowed_executable_identity
exec_decision ALLOW /bin/rm FORGED_BY_CHILD
supervisor_exit None None None
```

The forged `{"event":"exec_decision",…,"raw_exe":"/bin/rm",…}` line was emitted by the supervised Python child writing to its own stderr. From a downstream auditor's perspective (parsing each `{…}` line with `json.loads`), the forged record is indistinguishable from a real supervisor decision.

Root cause (`guard/usernotify_exec_guard.c:502-538`): the supervisor's `write_decision_json` writes to `stderr`, and the supervisor never redirects the child's stderr. Parent and child share fd 2.

Variant (also live-demonstrated): a child that writes any non-newline-terminated string to stderr immediately before a syscall trap will cause the next supervisor JSON record to be prepended with that bytes, breaking strict JSON-per-line parsers:

```
$ … python3 -c 'import sys, subprocess; sys.stderr.write("CHILD-STDERR-NOISE-"); sys.stderr.flush(); subprocess.run(["/bin/echo","x"])' …
…
CHILD-STDERR-NOISE-{"event":"exec_decision",…,"raw_exe":"/bin/echo",…}
```

Why this matters: the audit trail is the load-bearing artifact of this lab. A trail that the supervised process can write into is not an audit trail; it is a shared log file. Any downstream review (this audit included) must validate that records came from the supervisor, not the supervised.

Mitigation directions (any one closes it):
- Open a dedicated audit fd (e.g. `O_APPEND` to a file, or a pipe to a separate logger) **before** `fork()`, write all supervisor records there, and route the child's stderr to a separate file.
- Frame each record with a HMAC computed over the record body using a key the supervisor holds and the child cannot read (the child is in the same UID, so an in-process key is not enough; a per-run key derived from a parent-only fd works).
- Prefix every supervisor record with a sentinel byte sequence the child cannot write (only credible if combined with separating the streams).

This is not architectural; it is one fd. Do it before Sprint 3.

---

## Critical Finding 2 — Supervisor is killable by the child (severity: HIGH for "supervisor outside the trap boundary" framing)

Live demonstration, just now:

```
$ timeout 8 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os, signal, time
ppid = os.getppid()
os.kill(ppid, signal.SIGTERM)
time.sleep(1.0)
… try /bin/rm via subprocess …
' 2>&1 …
```

Sentinel file output:

```
BEFORE pid=3227364 ppid=3227354
AFTER kill, attempting rm
rm exception: OSError(38, 'Function not implemented')
DONE
```

Observations:

1. The child reached `os.kill(ppid, SIGTERM)` and the supervisor died (the parent shell saw exit 143 = 128+15 from the supervisor process group).
2. **No `supervisor_exit` JSON record was written** — the supervisor was killed before it could log shutdown. The audit trail is silently truncated.
3. After the supervisor died, the listener fd was closed by the kernel; further filtered syscalls in the child returned `ENOSYS` (errno 38). So the kernel does fail-safe on the listener-closed condition, and **`/bin/rm` did not actually run**. The child is left in a broken state where filtered syscalls return `ENOSYS`, but it can still execute non-filtered syscalls (open/read/write etc.) and run shell builtins inside an already-running allowed binary.

Why this matters for the framing: the candidate writes "the supervisor is no longer under the supervised child seccomp filter" and "outside the trap boundary." That is mechanically true — the supervisor is not seccomp-filtered. But the trust boundary is wider than seccomp:
- supervisor and child share UID, so `kill(ppid, SIGTERM)` is permitted.
- supervisor and child share PID namespace, so the child can read `/proc/<ppid>/comm`, `/proc/<ppid>/cmdline`, send signals, attach via ptrace if `kernel.yama.ptrace_scope=0` (default on this machine? not tested).
- supervisor and child share filesystem and mount namespace, so the supervisor's `realpath()` resolves in the same namespace as the child's exec.

So "outside the trap boundary" is correct in the narrow seccomp sense and **misleading** in the operational sense. The child can DoS the audit, leak supervisor identity, and (in this run) prevent the `supervisor_exit` record from ever appearing.

Mitigation directions:
- Run the supervisor in a separate PID namespace, or under a different UID, so `kill(ppid, …)` and `/proc` introspection are blocked. Container or `unshare(CLONE_NEWPID|CLONE_NEWUSER)` would do it.
- At minimum, install a `SIGTERM`/`SIGINT` handler in the supervisor that emits a final `supervisor_exit` record (with `reason=killed_by_signal`) before exiting.
- Use `prctl(PR_SET_PDEATHSIG)` is not the answer here — that goes the wrong direction (kills the *child* if parent dies). What's needed is the inverse: don't let the child reach the supervisor.

---

## Critical Finding 3 — `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU window is documented but produced an audit-log inconsistency live (severity: MEDIUM, but the inconsistency is HIGH for audit fidelity)

The candidate honestly documents that ALLOW still uses `CONTINUE` and that the kernel re-reads userspace memory after the supervisor's decision (`SPRINT2_IDENTITY_HARDENING_20260430.md` "Remaining Limitations"). `SECCOMP_IOCTL_NOTIF_ID_VALID` is checked before SEND, but as the candidate also notes, `NOTIF_ID_VALID` only confirms the notif is still outstanding — it does not prevent the userspace memory mutation race.

Live, just now, against the canonical race (one thread mutating the path string while a fork loop calls `execve` against it):

```
$ timeout 6 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import ctypes, os, threading
libc = ctypes.CDLL(None, use_errno=True)
buf = ctypes.create_string_buffer(b"/usr/bin/git\x00\x00\x00\x00")
argv = (ctypes.c_char_p * 3)(buf.raw[:14], b"--version", None)
stop = [False]
def mutator():
    while not stop[0]:
        ctypes.memmove(buf, b"/bin/rm\x00", 8)
        ctypes.memmove(buf, b"/usr/bin/git\x00", 13)
threading.Thread(target=mutator, daemon=True).start()
for i in range(50):
    pid = os.fork()
    if pid == 0:
        libc.execve(buf, argv, (ctypes.c_char_p*1)(None))
        os._exit(127)
    os.waitpid(pid, 0)
stop[0] = True
'
```

Of 50 attempts: stdout shows `git version 2.43.0` printed 26 times (i.e. 26 successful execves of git). Audit stream contains a mix of:
- `decision:ALLOW raw_exe:/usr/bin/git realpath:/usr/bin/git` (correct ALLOW),
- `decision:BLOCK raw_exe:/bin/rm realpath:/usr/bin/rm argv:["/usr/bin/git","--version"]` (the supervisor read the post-mutation path bytes for `raw_exe` but read the pre-mutation argv pointer — **inconsistent record where `raw_exe` and `argv[0]` disagree**).

In this run, the race did not deterministically achieve "ALLOW logged for git but rm actually executed" (the visible outputs were all `git version 2.43.0`), and the kernel-level re-read of the path may also see the mutation flap back and forth such that whatever string is read at exec-time decides the actual binary. So: **I did not demonstrate a bypass against the policy** in the seconds I had to try. But I did demonstrate that **the audit record can already record disagreeing fields** (raw_exe says one thing, argv says another), which means a downstream parser cannot trust that `raw_exe` and `argv[0]` describe the same call.

This is consistent with the kernel documentation. The candidate's stated posture is correct: residual TOCTOU is named, and "complete TOCTOU elimination" is on the "claims still not allowed" list. I am not faulting the framing here. I am noting that an attacker who *does* win the race will produce an audit record where the supervisor's `realpath` and `sha256` reflect what was on disk at the supervisor's stat moment, not what the kernel actually executed — so an ALLOW record cannot be relied on as proof that the matching binary was the one that ran.

Mitigation: this is fundamentally what the kernel `man 2 seccomp_unotify` "TOCTOU considerations" warns about. The known fixes are (a) use `SECCOMP_IOCTL_NOTIF_ADDFD` with a supervisor-validated fd and synthesise the syscall yourself, or (b) use `execveat` against an fd the supervisor opened and validated, instead of `CONTINUE`.

---

## Secondary Finding 1 — `/proc/self/exe` resolves in the supervisor's process, not the child's (audit-fidelity bug)

Live demonstration:

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os
os.execv("/proc/self/exe", ["/proc/self/exe", "-c", "print(\"reexec ok\")"])
'
```

Supervisor records:

```
{... "raw_exe":"/proc/self/exe","realpath":"/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard",
     "dev":66306,"ino":58990515,"sha256":"40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415", ...}
```

The supervisor took the literal string `/proc/self/exe` from child memory, called `realpath()` from the *supervisor's* process context, and resolved it to the **supervisor's own binary** (the guard executable at `/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard`). The supervisor then BLOCKed because the supervisor binary is not in the allowlist.

Variant: with a hostile policy that does include the supervisor binary path, an `execv("/proc/self/exe", …)` from a child gets ALLOWed under the supervisor's identity, then the kernel re-execs `/proc/self/exe` from the **child's** perspective (which is `/usr/bin/python3.12`). The supervisor logs supervisor-binary identity; the kernel runs the child's actual exe. **Audit fidelity violation.**

In the default Sprint 2 policy this is not a bypass (the supervisor binary isn't on the allowlist, and the child's exe is python3 which is allowlisted, so the recorded identity is wrong but the actual exec is allowed-by-coincidence). It would become a bypass if the operator ever placed the supervisor binary on the allowlist (e.g., self-hosted dogfooding) or if the child's actual `/proc/self/exe` resolves to something not allowed.

Mitigation: the supervisor must resolve symbolic paths from the child's perspective. Read the path through `/proc/<child_pid>/root/<path>` or open via `/proc/<child_pid>/cwd/<path>` for relative paths and follow `/proc/<child_pid>/exe` explicitly when the child's path is `/proc/self/exe`. The current code reads `/proc/<child_pid>/cwd` for cwd capture (good) but does not re-anchor `realpath()`.

---

## Secondary Finding 2 — Policy parser is a `strstr`/`strchr` walk, not a JSON parser

`load_policy` (`guard/usernotify_exec_guard.c:308-373`) finds `"allowed_executables"` via `strstr`, then takes the first `[` and `]` after it as the array bounds, then scans every quoted string between them. This is fragile in three ways I verified live:

1. If `"allowed_executables"` is present but its value is **not** a JSON array (e.g. a string), the parser silently uses the **next** `[ … ]` block in the file as the allowlist:
   ```
   $ cat /tmp/spoof4.policy.json
   { "policy_id": "spoof",
     "allowed_executables": "should_be_array",
     "extra": [ "/bin/echo" ],
     "more_paths": [ "/bin/rm" ] }
   $ ./bin/usernotify_exec_guard --policy /tmp/spoof4.policy.json /bin/echo this_should_block
   {... "decision":"ALLOW","reason":"allowed_executable_identity","raw_exe":"/bin/echo", ...}
   this_should_block
   ```
   Result: `/bin/echo` was allowed, even though the policy's `allowed_executables` field is `"should_be_array"` (a string). The parser walked forward to the next array.

2. JSON escapes in policy strings (`"`, `\\"`, etc.) are not interpreted — so `"extra` becomes a literal path that fails to resolve. Not a bypass, but a footgun.

3. `policy_id` parsing is naive `strchr`-of-quote — a `policy_id` value that contains an embedded `"` will be truncated mid-string and the truncated value is what gets logged.

None of these escalate to a fail-open today, because (a) the policy file is operator-controlled, and (b) `add_policy_path` calls `realpath` on every candidate and exits if it doesn't resolve. But a future operator who writes a policy that is structurally weird (comments, alternate field names, multi-array files for environment-specific allows) can land in the silently-walks-to-next-array failure mode. **Replace this with a real JSON parser before Sprint 3** (jansson, cJSON, or even hand-written but state-machine-based — not strstr).

---

## Secondary Finding 3 — argv capture truncates per-arg at 512 bytes; no field marks truncation

`capture_argv_json` (`guard/usernotify_exec_guard.c:410-442`) reads each arg into a 512-byte buffer via `read_child_string`. The whole argv JSON buffer is 2048 bytes. If an arg exceeds 512 bytes, the captured string is silently truncated; if the total argv exceeds 2048 bytes, capture stops mid-array. Long-path test live (1537-byte path passed as argv[0]):

```
"argv":["/tmp/dp/aaaaaaa…aaaaaaaa","-c","echo hi"]
```

The argv[0] was truncated mid-string with no marker. The `raw_exe` (4096-byte buffer) captured the full path, so this is purely an argv-fidelity issue, not a decision-fidelity issue. But for an audit trail used to reconstruct a chain of agent-issued commands, silent argv truncation is a hole. Add an `"argv_truncated":true` flag when the buffer fills.

---

## Secondary Finding 4 — `MAX_ARGV_CAPTURE = 8` silently caps captured argv length

Same function caps the argv array at 8 entries (`for (size_t i = 0; i < MAX_ARGV_CAPTURE && used < out_len; i++)`). A `bash -c '…'` is fine; a `python3 -m pip install foo bar baz qux quux corge grault garply waldo` is not — only the first 8 args are recorded. Not a bypass; a fidelity gap. Document it or raise the cap.

---

## Secondary Finding 5 — `file_sha256` shells out to `/usr/bin/sha256sum` from inside the supervisor

`file_sha256` (`guard/usernotify_exec_guard.c:217-251`) `fork`+`execl`s `/usr/bin/sha256sum`. This works on this machine because `/usr/bin/sha256sum` exists and is on a stable path. But:

- The supervisor relies on a binary outside the allowlist; if `/usr/bin/sha256sum` were modified between policy-load (which sha256s every allowed path) and decision-time (which sha256s the resolved exe), the recorded sha256 in the audit trail would reflect an attacker-controlled value. This is theoretical against the current threat model (operator-controlled `/usr/bin/sha256sum`), but it's a dependency on an unhardened binary.
- The supervisor is doing a `fork+exec` per ALLOW/BLOCK decision, which costs ~2-5 ms and adds a process accounting record. For high-frequency execve workloads this is noticeable.
- Sprint 2 hashes are computed *after* the supervisor's `stat()` already captured `dev`/`ino`. There is a tiny window where the file at the resolved path could be replaced between stat and sha256 computation; the audit log would then carry mismatched `(dev, ino, sha256)` and not flag it.

Mitigation: link against an in-process sha256 implementation (libcrypto, libsodium, or a vendored single-file SHA256 like `picohash`). One paragraph of code; closes the dependency and the cross-call window.

---

## Secondary Finding 6 — Hardlink/cp variants cleanly blocked (the audit *does* find a strong identity check)

I tested:
- `cp /bin/rm /tmp/rmcopy && ln /tmp/rmcopy /tmp/git` (same-fs hardlink to a copy of rm, then named "git"). Block: `realpath=/tmp/git ino=213520172 sha256=8e3faaa5…`. Correctly blocked because the realpath does not match any allowlist entry. (Hardlink across `/bin → /tmp` failed with EPERM at the OS level, which is unrelated to the guard.)
- The realpath check correctly resolves through one level of symlink (`/tmp/python3 → /bin/rm` resolves to `/usr/bin/rm`, dev/ino match `/usr/bin/rm`, but the *configured* allowlist entry for python3 is `/usr/bin/python3`, so the `strcmp(entry->real_path, real_path)` fails and BLOCK fires).

The identity check is structurally correct: it requires `(dev, ino, real_path)` all three to match. A hardlink that produces matching dev/ino but a different real_path is still blocked. A symlink that produces matching real_path but is rooted at a non-allowed location is still blocked. **This is the part of Sprint 2 that genuinely works.**

---

## What This Audit Does Not Find

I tried but did not produce a bypass via:
- Symlink to allowed binary placed at a non-allowed path (correctly blocked).
- Hardlink to non-allowed binary placed under an allowed-looking name (correctly blocked).
- PATH hijack (correctly blocked).
- Long path > PATH_MAX-ish (correctly blocked, raw_exe captured fully).
- JSON injection via argv with `"`, `\`, control bytes, newlines (correctly escaped).
- JSON injection via path containing `"` (correctly escaped).
- Malformed/empty/missing/non-array policy files (all fail-closed with exit 2).
- Policy with non-existent path (fail-closed with exit 2).
- Killing the supervisor and then re-execing `/bin/rm` from the orphaned child (kernel returns ENOSYS for filtered syscalls when listener fd is closed — this is the intended safe-fail).
- `setsid()` to detach: child remains under the seccomp filter; further execve still notified.
- TOCTOU race using a parallel mutator thread: I observed audit-log inconsistencies (raw_exe vs argv disagreeing) but did not reliably win the race to actually run an unauthorized binary in the seconds I had. A determined attacker with more attempts or a tighter race window may; the kernel docs explicitly warn this is possible with `CONTINUE`.

---

## Honest Claim That Should Replace the Sprint 2 Headline

Current claim (`SPRINT2_AUDIT_20260430.md`):

> "A local seccomp user-notify guard can enforce a file-backed executable identity allowlist, reject the tested basename rename, symlink, and PATH-hijack bypasses, preserve nested execve trapping, conservatively block the tested execveat path, and emit JSON-safe audit records."

Tightened claim that survives this audit:

> "A local SECCOMP_RET_USER_NOTIF supervisor on this machine intercepts execve and execveat from a supervised child, applies a file-backed allowlist that compares (realpath, st_dev, st_ino) of the resolved binary against entries from `policy/sprint2.allow.json`, denies by default with EPERM, conservatively blocks all execveat with `execveat_not_supported_in_sprint2`, validates the notification id with `SECCOMP_IOCTL_NOTIF_ID_VALID` before responding, and emits one enriched JSON record per decision plus a `supervisor_exit` record on clean shutdown. The Sprint 1 basename-rename, symlink, and PATH-hijack bypasses are verified blocked. The seccomp filter is installed only in the child and the listener fd is handed to the supervisor over a Unix socket, so the supervisor itself is not under the filter. The supervisor's audit records share fd 2 with the child and can be **forged or interleaved** by the supervised process; the supervisor and child share UID and PID namespace, so the child can **kill the supervisor** with `kill(getppid(), SIGTERM)` (which silently truncates the audit stream — no `supervisor_exit` line); the ALLOW path still uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE`, which carries the kernel-documented userspace-memory TOCTOU window between the supervisor decision and the kernel's re-read at exec time. Sprint 2 is a stronger mechanism proof than Sprint 1 with a real identity check and a real audit schema; it is not a security boundary."

The Sprint 2 self-claim is honest about the third item (`CONTINUE` TOCTOU). It does not name the first two (audit forgery, killable supervisor). Those should be added to the "Remaining Limitations" section, or fixed.

---

## Sprint 3 Prerequisites (audit-derived)

Before adding Docker / OpenHands work, this audit recommends closing in this order:

1. **Separate the audit stream from child stderr.** Open a dedicated supervisor-only output fd (file or pipe) before `fork()`. Route the child's stderr to a separate file. Closes Critical Finding 1.
2. **Move the supervisor outside the child's signal/PID/UID reach.** A separate PID namespace via `unshare(CLONE_NEWPID)` is the lightweight version; running the supervisor under a different UID is the heavier version. At minimum, install a `SIGTERM`/`SIGINT`/`SIGHUP` handler in the supervisor that emits a final `supervisor_exit{reason=killed_by_signal}` record. Closes Critical Finding 2.
3. **Replace `strstr`/`strchr` policy parsing with a real JSON parser.** jansson or a vendored single-header parser. Closes Secondary Finding 2.
4. **Inline SHA256.** Drop the fork+exec to `/usr/bin/sha256sum`; link a small SHA256 implementation. Closes Secondary Finding 5 and removes a runtime dependency.
5. **Anchor `realpath` resolution in the child's filesystem context.** Use `/proc/<child_pid>/root/<path>` or open via `/proc/<child_pid>/cwd/<rel>` so `/proc/self/exe` and similar magic paths resolve from the child's perspective, not the supervisor's. Closes Secondary Finding 1.
6. **Document or fix the residual `CONTINUE` TOCTOU.** The honest documentation is already there; the production fix is `SECCOMP_IOCTL_NOTIF_ADDFD` + supervisor-anchored `execveat`. This is the larger architectural lift; do (1)-(5) first.
7. **Add an `"audit_record_truncated":true` field when argv or any captured field hits the buffer cap.** Closes Secondary Findings 3 and 4.

After (1)–(5), Sprint 3 can credibly add Docker. (6) and (7) can run in parallel with Docker work.

---

## Discipline Observations (worth preserving)

What the candidate did right and should keep doing every sprint:

- **Failed run preserved unchanged**: `proofs/sprint2_runs/sprint2-20260430T220518Z` carries `pass=10 fail=2` with the exact failing case directories. Compare this to a culture where a failed run gets quietly deleted; that is the discipline that earns this audit chain its credibility.
- **Three passing replays at increasing test count**: `220552Z (pass=11)`, `220610Z (pass=11 reproducibility)`, `220722Z (pass=12 after adding execveat)`. Re-running shows the test set converges, not flaps.
- **SHA256 anchoring of source and binary in every replay** (`sha256s.txt` per run). Makes my re-derivation a one-liner.
- **Explicit "Claims Still Not Allowed" list** in both the proof memo and the audit memo. Prevents anyone reading either as more than a mechanism proof.
- **Honest naming of the residual `CONTINUE` TOCTOU** without trying to wave it away with `NOTIF_ID_VALID`. The candidate gets that `NOTIF_ID_VALID` does not address the userspace memory race; this is the second time in a row the candidate has voluntarily named a known-flaw rather than letting an auditor find it.
- **Per-case directories with stdout, stderr, exit_code, command, json_check** under each run root. Makes "show me what actually happened in case X" trivial.
- **Replay script is idempotent and self-documenting**: it compiles, runs each case in its own subdirectory, and records hashes. Sprint 3 should keep this shape.

These are the same patterns that earned the Sprint 1 audit its credibility. Do not regress.

---

## Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

# Re-derive
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
  -> 58b8409de0c53d4be2e742cac11877902b1c6249c9e8a4a06e7b053314a4aae2  guard/usernotify_exec_guard.c
  -> 40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415  bin/usernotify_exec_guard
wc -l guard/usernotify_exec_guard.c
  -> 672 guard/usernotify_exec_guard.c

# Re-run replay live
bash scripts/replay_sprint2_identity.sh
  -> pass=12 fail=0

# Sprint 1 bypasses re-tested
cp /bin/rm /tmp/git
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/git --version
  -> {"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/tmp/git","realpath":"/tmp/git",
      "sha256":"8e3faaa5eb4a2a4d0e2788fe442bcac6d604be5a0c5a9f09d08f06e3a3fcf570",...}; exit 126

ln -sf /bin/rm /tmp/python3
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/python3 --version
  -> {"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/tmp/python3","realpath":"/usr/bin/rm",
      "sha256":"8e3faaa5...",...}; exit 126

mkdir -p /tmp/hi && cp /bin/rm /tmp/hi/git
env PATH=/tmp/hi:$PATH timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json git --version
  -> {"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/tmp/hi/git","realpath":"/tmp/hi/git",
      "sha256":"8e3faaa5...",...}; exit 126

# Hardlink probe
cp -p /bin/rm /tmp/rmcopy && ln /tmp/rmcopy /tmp/git
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/git --version
  -> {"decision":"BLOCK","realpath":"/tmp/git","sha256":"8e3faaa5...",...}; exit 126

# /proc/self/exe identity confusion (audit fidelity)
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os; os.execv("/proc/self/exe", ["/proc/self/exe", "-c", "print(\"reexec ok\")"])'
  -> second record: realpath=/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard
     (supervisor's own binary, not the child's python3.12); BLOCK by coincidence.

# Long path PATH_MAX edge
mkdir -p /tmp/dp; (1500-char path); cp /bin/bash $LONG/sh
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json $LONG/sh -c 'echo hi'
  -> BLOCK, raw_exe captured fully, argv[0] truncated to ~512 bytes silently; exit 126

# Policy edge cases (all fail-closed)
./bin/usernotify_exec_guard --policy /tmp/nonexistent.json /bin/echo hi -> exit 2 "read policy: No such file or directory"
./bin/usernotify_exec_guard --policy /tmp/empty.policy.json /bin/echo hi -> exit 2 "policy missing allowed_executables"
./bin/usernotify_exec_guard --policy /tmp/no_allow.policy.json /bin/echo hi -> exit 2 "policy missing allowed_executables"
./bin/usernotify_exec_guard --policy /tmp/empty_allow.policy.json /bin/echo hi -> exit 2 "policy has no allowed executable paths"
./bin/usernotify_exec_guard --policy /tmp/bad_path.policy.json /bin/echo hi -> exit 2 "policy path does not resolve: /does/not/exist"
./bin/usernotify_exec_guard --policy /tmp/garbage.policy.json /bin/echo hi -> exit 2 "policy missing allowed_executables"
./bin/usernotify_exec_guard --policy /tmp/trunc.policy.json /bin/echo hi -> exit 2 "policy allowed_executables is malformed"

# Policy parser confusion (Secondary Finding 2)
echo '{"policy_id":"spoof","allowed_executables":"should_be_array","extra":["/bin/echo"],"more_paths":["/bin/rm"]}' > /tmp/spoof4.policy.json
./bin/usernotify_exec_guard --policy /tmp/spoof4.policy.json /bin/echo this_should_block
  -> ALLOW (parser walked forward past string-valued allowed_executables to next [...] block); exit 0

# Audit forgery (Critical Finding 1)
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import sys; sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_BY_CHILD\"}\n")'
  -> downstream parser sees three exec_decision lines; one is forged; supervisor saw only one execve.

# Stderr interleaving (Critical Finding 1 variant)
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import sys, subprocess; sys.stderr.write("CHILD-STDERR-NOISE-"); sys.stderr.flush(); subprocess.run(["/bin/echo","x"])'
  -> output line: "CHILD-STDERR-NOISE-{"event":"exec_decision",...}"  (line does not start with '{' — naive parser drops it; less-naive parser fails)

# Kill supervisor (Critical Finding 2)
timeout 10 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os, signal, subprocess, time
os.kill(os.getppid(), signal.SIGTERM)
time.sleep(1)
rc = subprocess.run(["/bin/rm","--version"], capture_output=True, text=True)
... write to /tmp/sentinel.out ...'
  -> supervisor dies with SIGTERM (no supervisor_exit JSON record)
  -> child's subsequent /bin/rm execve returns ENOSYS (kernel safe-fail when listener fd closed)
  -> sentinel: "rm exception: OSError(38, 'Function not implemented')"

# TOCTOU race (Critical Finding 3)
timeout 6 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '...mutator + 50 fork+execve...'
  -> 26 successful git executions, audit shows mixed ALLOW (raw_exe=/usr/bin/git) and BLOCK (raw_exe=/bin/rm)
     records with argv[0] always="/usr/bin/git" (argv read at one point, path at another → inconsistent record)

# Audit field completeness
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/git --version 2>/tmp/allow.json
timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /bin/rm --version 2>/tmp/block.json
  -> exec_decision keys: event,timestamp,policy_id,pid,syscall,notif_id,decision,reason,raw_exe,realpath,cwd,dev,ino,sha256,argv
  -> supervisor_exit keys: event,timestamp,policy_id,child_exit
  -> All headline fields present.

# Cleanup
rm -rf /tmp/dp /tmp/hi /tmp/git /tmp/python3 /tmp/rmcopy /tmp/git_hardlink /tmp/sentinel.out
rm -f /tmp/empty.policy.json /tmp/no_allow.policy.json /tmp/empty_allow.policy.json
rm -f /tmp/bad_path.policy.json /tmp/garbage.policy.json /tmp/relpath.policy.json
rm -f /tmp/trunc.policy.json /tmp/escape.policy.json /tmp/spoof.policy.json /tmp/spoof2.policy.json
rm -f /tmp/spoof3.policy.json /tmp/spoof4.policy.json /tmp/dual.policy.json /tmp/hostile.policy.json
rm -f /tmp/audit.json /tmp/audit2.json /tmp/race.stdout /tmp/race.stderr /tmp/interleave.stderr
rm -f /tmp/forge.stderr /tmp/allow.json /tmp/block.json
rm -rf '/tmp/a"b'
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint2_independent_review_a.md`
- Sprint 2 proof memo: `proofs/SPRINT2_IDENTITY_HARDENING_20260430.md`
- Sprint 2 self-audit: `proofs/SPRINT2_AUDIT_20260430.md`
- Sprint 2 command log: `proofs/SPRINT2_COMMAND_LOG_20260430.md`
- Sprint 2 replay script: `scripts/replay_sprint2_identity.sh`
- Sprint 2 policy: `policy/sprint2.allow.json`
- Sprint 2 source: `guard/usernotify_exec_guard.c` (672 lines, sha256 58b8409d…)
- Sprint 2 binary: `bin/usernotify_exec_guard` (sha256 40e156ab…)
- Sprint 2 latest passing run: `proofs/sprint2_runs/sprint2-20260430T221125Z` (created by my replay)
- Sprint 2 candidate's passing run: `proofs/sprint2_runs/sprint2-20260430T220722Z` (pass=12 fail=0)
- Sprint 2 preserved failed run: `proofs/sprint2_runs/sprint2-20260430T220518Z` (pass=10 fail=2, harness PATH bug)
- Sprint 1 prior audit: `proofs/AUDIT_20260430_sprint1_independent_review.md`
