# Sprint 2 — Independent Audit Review (Auditor B)

Date: 2026-04-30
Auditor: independent adversarial pass. Parallel Auditor A is running the same brief; this report is formed without coordination.
Posture: re-derive SHAs, re-run the harness from scratch, attempt new bypass classes, reason about residual TOCTOU.
Source of record: live commands run on this machine just now; bypasses tested in front of the audit log; outputs pasted literally.

---

## Audit Question

Did Sprint 2 close the Sprint 1 basename-bypass and audit-integrity findings honestly, and what new bypass classes does the realpath+dev+ino design open up? Is the headline `pass=12 fail=0` accurate, and is the operator's TOCTOU disclosure honest?

## Verdict

**Sprint 2 mechanism work is real and the headline is accurate.** All twelve harness probes reproduce green on independent re-run. The three Sprint 1 bypasses (copy-rename, symlink, PATH-hijack) are now closed by identity matching. The audit JSON contains every field promised in the headline. The `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU residual is *honestly disclosed in writing*, which is the right move because it is *not closed* — `SECCOMP_IOCTL_NOTIF_ID_VALID` does not mitigate the userspace-memory-rewrite race, only the supervised-pid-still-alive race.

Two findings worth naming before Sprint 3:

1. **Policy parser is `strstr`-based, not a real JSON parser** — fragile but not currently fail-open in the cases I tested. Sprint 3 should swap it for a real parser before the policy is exposed to attacker influence.
2. **Realpath of `/proc/self/exe` resolves in the supervisor's namespace, not the child's** — currently fail-closed (resolves to the guard binary itself, which is not allowlisted), but it's a wrong answer. The supervisor should resolve `/proc/self/exe` against `/proc/<child_pid>/root/proc/<child_pid>/exe`, or read the link explicitly via `readlinkat(child_proc_fd, "exe", ...)`.

The operator's posture (PASS for local identity hardening, NO production claim, residual TOCTOU disclosed) is correct. Recommend: independent audit gate cleared; Sprint 3 should fix the JSON parser and the /proc/self/exe resolution before adding Docker.

---

## What Verified Clean Independently

Re-derived from disk just now:

```
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
58b8409de0c53d4be2e742cac11877902b1c6249c9e8a4a06e7b053314a4aae2  guard/usernotify_exec_guard.c
40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415  bin/usernotify_exec_guard
wc -l guard/usernotify_exec_guard.c
672 guard/usernotify_exec_guard.c
```

Both match the hashes claimed in `SPRINT2_AUDIT_20260430.md`. Source grew from 228 lines (Sprint 1) to 672 lines (Sprint 2) — substantial, consistent with the claimed mechanism additions.

Re-ran the replay harness from scratch:

```
$ bash scripts/replay_sprint2_identity.sh
PASS compile gcc clean
PASS allow_git exit=0 json=valid
PASS direct_block_rm exit=126 json=valid
PASS direct_block_rm_output rm output absent
PASS bash_nested_block_rm exit=126 json=valid
PASS python_nested_block_rm exit=1 json=valid
PASS copy_rename_bypass_blocked exit=126 json=valid
PASS copy_bypass_output renamed rm did not execute
PASS symlink_bypass_blocked exit=126 json=valid
PASS env_path_bypass_blocked exit=126 json=valid
PASS json_escape_hostile_path exit=126 json=valid
PASS execveat_blocked exit=0 json=valid
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T221145Z
exit=0
```

Sprint 1 bypasses now blocked (live-demonstrated below). All audit JSON fields promised in the headline (pid, syscall, raw_exe, realpath, cwd, dev, ino, sha256, argv, reason, timestamp) verified present in both ALLOW and BLOCK records via `python3 json.loads`.

The operator's discipline shape is preserved:
- `proofs/sprint2_runs/sprint2-20260430T220518Z` is the *honestly preserved failed run* (pass=10 fail=2, harness-PATH bug, replay_summary.txt records the FAIL lines).
- Per-case stdout/stderr/exit_code captured under each run dir.
- Fixed-the-harness commit log lives in `SPRINT2_COMMAND_LOG_20260430.md` — they didn't rewrite history.
- `policy/sprint2.allow.json` carries a `policy_id` that the audit records also carry — provenance is consistent.

---

## Critical Findings

None at the security level. The Sprint 1 critical findings are closed.

---

## Secondary Findings

### Finding S1 — Policy parser is `strstr`-based, not real JSON (severity: MEDIUM, latent)

`guard/usernotify_exec_guard.c:308-373` `load_policy()`:

- Uses `strstr(buf, "\"policy_id\"")` then walks two `"` chars to extract the value.
- Uses `strstr(buf, "\"allowed_executables\"")`, then `strchr('[')`, then `strchr(']')`, then walks `"`-pairs in between, requiring entries to start with `/`.
- No nesting awareness. No escaped-quote awareness. No comment awareness.

Live-demonstrated edge cases:

```
# policy_id with escaped quote → audit field is garbled
echo '{"policy_id":"contains \"allowed_executables\"","allowed_executables":["/usr/bin/git"]}' > /tmp/tricky.json
$ guard --policy /tmp/tricky.json /usr/bin/git --version
{...,"policy_id":"contains \\",...}     # truncated at the first internal escaped quote
```

The audit's `policy_id` field gets truncated mid-value when the value contains escaped quotes. Not a security vulnerability; it is a *data-integrity bug in the audit trail's provenance field*.

Cases I tried that did **not** fail open:
- Decoy `"allowed_executables_*"` keys before the real one — strstr matches the longer key, `[`/`]` fenced, no quote-pairs inside → policy load fails closed with "no allowed executable paths".
- `[/bin/rm]` as a string value adjacent to `"allowed_executables"` — no quote chars between `[` and `]` in the decoy → no entries parsed → fail closed.
- Malformed JSON, missing `allowed_executables`, empty array, non-existent path, relative paths — all fail closed (exit 2 or strict ignore).

What I could not produce in a quick adversarial pass: an attacker-controlled policy file that adds executables the operator did not intend. The parser is fragile but, in the cases I exercised, it errs strict. **However**: a custom JSON parser is a Sprint-3 footgun. Replace it with a real JSON library before Docker/policy-templating turns this into an attack surface.

### Finding S2 — `/proc/self/exe` resolves in the supervisor's namespace (severity: LOW, fail-closed)

In `resolve_child_exe()` (line 387-408), the supervisor calls `realpath(operator, real)`. If the child execs `/proc/self/exe`, the operator is `/proc/self/exe`, and `realpath` is called *from the supervisor process*. `/proc/self` from the supervisor points to the supervisor itself, not the child. So:

```
$ guard --policy ... /proc/self/exe --version
{..."raw_exe":"/proc/self/exe","realpath":"/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard"...}
```

This is *currently fail-closed* (the supervisor binary's identity is not in the allowlist, so it is BLOCKed). But it is the wrong answer — the resolved path should reflect the *child's* `/proc/self`, which is `/proc/<child_pid>/exe`. Today's behavior: an audit reader sees that the child tried to exec the supervisor itself, which is misleading.

Workaround: resolve via `/proc/<child_pid>/root/proc/<child_pid>/exe`, or `readlinkat(child_proc_fd, "exe", ...)`. The numeric form `/proc/<child_pid>/exe` does work correctly, verified live:

```
$ guard ... /usr/bin/python3 -c 'import os; pid=os.getpid(); os.execv(f"/proc/{pid}/exe", ["python3","--version"])'
{..."raw_exe":"/proc/3227899/exe","realpath":"/usr/bin/python3.12",...,"decision":"ALLOW"...}
```

### Finding S3 — argv capture truncates per-arg at 512 bytes (severity: INFORMATIONAL)

`MAX_ARGV_CAPTURE = 8`, per-arg buffer `arg[512]`, total `argv_json[2048]`. A long path or long argument silently truncates without an "argv_truncated":true marker in the JSON. Verified: a ~2444-char argv[0] was captured to ~512 bytes, JSON remained valid (no parse failure), but the audit record loses fidelity about what was launched. Add a `"argv_truncated"` boolean if any arg got cut.

### Finding S4 — Supervisor exit on SIGKILL produces no orphan-record (severity: INFORMATIONAL, fail-safe)

Live-tested: a supervised allowed Python child can `kill(getppid(), SIGKILL)` to terminate the supervisor. After the kill:

- The child's seccomp filter persists (process-attached).
- The kernel-side listener becomes unreachable.
- Subsequent `execve` from the child returns `ENOSYS` (errno 38).
- No `supervisor_exit` audit record is emitted because the supervisor was hard-killed before its own exit path.

This is **fail-safe**: the child cannot escape by killing the supervisor, because the filter survives. But the audit trail has a silent gap — a downstream parser sees `exec_decision` records and then nothing, with no reason. Sprint 3: consider a heartbeat or a `prctl(PR_SET_PDEATHSIG, SIGKILL)` *in reverse* (the child kills itself if the supervisor dies) to make the orphaned-listener state observable. Or write a brief `supervisor_killed` line via a separate watcher.

### Finding S5 — Residual TOCTOU on `CONTINUE` is honestly disclosed but not mitigated (severity: HIGH if claimed otherwise; not claimed)

The Sprint 1 critical finding 2 (path-rewrite-during-CONTINUE TOCTOU) is *not closed*. Source line 604 still sets `resp.flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE` on the ALLOW path. The kernel re-reads the userspace path argument when continuing the syscall.

The `SECCOMP_IOCTL_NOTIF_ID_VALID` check (line 597) checks whether the supervised pid still has *that notification id* outstanding. It does NOT prevent the supervised child from rewriting its own argv pointer or the path string in its own memory between the moment the supervisor calls `process_vm_readv` and the moment the kernel re-resolves the path. The operator writes this clearly in `SPRINT2_IDENTITY_HARDENING_20260430.md` lines 184-193 and again in `SPRINT2_AUDIT_20260430.md` lines 95-105. That's the right disclosure.

Adversarial probe: I ran a swap loop on a symlink (`/tmp/race/exe` flipping between `/usr/bin/python3` and `/bin/rm`) and ran the guard 30 times against it. Decisions consistently matched the symlink target *as resolved by the supervisor's realpath*. I did not catch a "ALLOW python3, kernel-resolved-as-rm" case in this brief test. The race window between supervisor `process_vm_readv` → policy decision → `NOTIF_SEND` → kernel re-resolve is small and process_vm_readv is fast — but it exists. Mitigations are documented in the kernel `seccomp_unotify(2)` man page (use `SECCOMP_IOCTL_NOTIF_ADDFD`, or refuse-and-resynth).

This does not affect Sprint 2's headline because the headline does not claim TOCTOU elimination. It does block any Sprint 3 claim that goes near "production-grade".

---

## What This Audit Does Not Find

The bypass classes I attempted that survived Sprint 2 and are correctly blocked:

- `cp /bin/rm /tmp/git`-style basename collision: now BLOCKed by realpath+dev+ino mismatch. Verified live below.
- `ln -sf /bin/rm /tmp/python3`-style symlink: now BLOCKed because realpath resolves through the symlink to `/usr/bin/rm`. Verified live below.
- `PATH=/tmp/hi guard git`-style PATH-hijack: BLOCKed because realpath on the resolved `/tmp/hi/git` does not match any allowlist entry. Verified live below.
- Hardlink to `/bin/rm`: Linux denies the link itself for non-root in this environment (`ln: failed to create hard link '/tmp/hardgit' => '/bin/rm': Operation not permitted`). Even constructing `/tmp/myrm` (a non-root copy of rm) and hardlinking that to `/tmp/myalias_python3`: BLOCKed because realpath of the alias is `/tmp/myalias_python3` (or wherever the link sits), which is not in the allowlist. The dev+ino match the source, but the realpath does not — and the policy check requires *all three* (dev, ino, realpath) to match.
- `/proc/self/exe` from a non-allowed-binary context: BLOCKed (resolves to the guard binary itself, which is not allowlisted; see Finding S2).
- Relative paths via `chdir`: correctly resolved using `/proc/<child_pid>/cwd`. Verified live: `chdir('/tmp/confuse'); execv('./relrm',...)` resolved to `/tmp/confuse/relrm`, BLOCKed.
- Long path edge (~2444 chars): BLOCKed correctly; `raw_exe` and `realpath` fields handled the full length; `argv` truncated per-arg at 512 bytes but JSON remained well-formed.
- JSON injection via argv with quotes / newlines / backslashes / control bytes / UTF-8: correctly escaped; all output lines parsed by `python3 json.loads`.
- JSON injection via path containing a `"`: harness already exercises this; correctly escaped.
- Parallel execve from bash (`/bin/rm --version &` x10, `wait`): all 10 BLOCKed; the supervisor's poll/recv/respond loop handles concurrency.
- Child SIGKILL of the supervisor: filter persists; further execve returns ENOSYS; child cannot escape. (Logging gap, not security gap — Finding S4.)
- Malformed/missing/empty policy files: all fail closed with exit 2.
- Misleading `"allowed_executables_*"` decoy keys, empty bracket sections, non-`/`-prefixed entries: all fail closed.

I did not test:
- Bind mounts (requires root).
- Mount namespace shenanigans on the child (requires root or unshare without seccomp interference).
- A reliable userspace-memory-rewrite TOCTOU exploit against the CONTINUE re-resolution. The window exists; weaponizing it cleanly was outside this audit's time budget. Treat as a known residual.

---

## Honest Claim That Survives This Audit

The operator's current Sprint 2 claim, from `SPRINT2_AUDIT_20260430.md`:

> "A local seccomp user-notify guard can enforce a file-backed executable identity allowlist, reject the tested basename rename, symlink, and PATH-hijack bypasses, preserve nested execve trapping, conservatively block the tested execveat path, and emit JSON-safe audit records."

This claim is accurate as written. I would only tighten one phrase: add "by realpath+device+inode triple-match against entries pre-resolved at policy load" to make the mechanism unambiguous to a reviewer who hasn't read the source. Otherwise it stands.

The "Claims Still Not Allowed" list in `SPRINT2_AUDIT_20260430.md:81-91` is exactly right and should be kept verbatim.

---

## Sprint 3 Prerequisites

This audit recommends, in order, before any Docker work:

1. **Replace the `strstr`-based policy parser with a real JSON library** (jansson, json-c, or a vendored single-header). Closes Finding S1's latent risk. Same `policy.json` format; better robustness.
2. **Fix `/proc/self/exe` resolution to use `/proc/<child_pid>/exe`.** Closes Finding S2. Today's fail-closed behavior is correct but the audit log lies about the resolved binary.
3. **Add `argv_truncated` boolean and `argv_total_count` to JSON when capture truncates.** Closes Finding S3.
4. **Decide what to do about the `CONTINUE` residual TOCTOU.** Either (a) switch to `SECCOMP_IOCTL_NOTIF_ADDFD` with a re-emitted execve against a validated FD, closing Finding S5; or (b) keep the disclosure language and *do not advance to a "production hardened" claim*. The honest move here is (b) with explicit residual posture in the README, until (a) ships in Sprint 4.
5. **Add a watcher / heartbeat record so a SIGKILLed supervisor leaves a visible audit gap marker** (from a small forked watcher process or a `prctl(PR_SET_PDEATHSIG)` self-killing child). Closes Finding S4.

After (1)–(5), Docker. Not before. Adding a container layer over a fragile string-based policy parser is the wrong order of operations — reviewers will assume the container shoulders integrity weight that the guard's policy load doesn't carry.

---

## Discipline Observations (worth preserving)

What the operator continued to do right between Sprint 1 and Sprint 2:

- Re-derivable provenance (SHAs match across audit memo, command log, replay run dir). Re-derivation took me 30 seconds.
- Failed run preserved verbatim (`sprint2-20260430T220518Z` with `pass=10 fail=2` and the FAIL lines for `env_path_bypass_blocked` still in `replay_summary.txt`). This is the right move — do not edit history when the harness was at fault.
- Per-run sub-directories with stdout/stderr/exit_code/command — diagnostic surface is preserved without me needing to re-run cases.
- Honest disclosure of the `CONTINUE` TOCTOU residual *in the same memo as the PASS verdict*, not buried elsewhere. This is the difference between an honest pass and a marketing pass.
- "Claims Still Not Allowed" list expanded between sprints (now includes "fd-relative `execveat` identity support" and "that path-based `CONTINUE` allows are TOCTOU-hardened"). Each new ability gained adds a new disallowed claim — the right reflex.
- Auditor B (this report) and Auditor A run independently; the operator did not pre-coordinate the audit briefs. That is the correct adversarial posture.

These habits are the actual differentiator. Keep doing them on every sprint.

---

## Commands Used For This Audit

```
$ cd /home/blazingradar/agent-exec-guard-lab

$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
58b8409de0c53d4be2e742cac11877902b1c6249c9e8a4a06e7b053314a4aae2  guard/usernotify_exec_guard.c
40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415  bin/usernotify_exec_guard

$ wc -l guard/usernotify_exec_guard.c
672 guard/usernotify_exec_guard.c

$ bash scripts/replay_sprint2_identity.sh
[...]
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T221145Z
exit=0

# Sprint 1 bypass 1 — copy /bin/rm to /tmp/git
$ cp /bin/rm /tmp/git
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /tmp/git --version
{"event":"exec_decision",...,"pid":3224990,"decision":"BLOCK","reason":"blocked_executable_identity",
 "raw_exe":"/tmp/git","realpath":"/tmp/git","sha256":"8e3faaa5...","argv":["/tmp/git","--version"]}
execvp: Operation not permitted
{"event":"supervisor_exit",...,"child_exit":126}
exit=126

# Sprint 1 bypass 2 — symlink /tmp/python3 -> /bin/rm
$ ln -sf /bin/rm /tmp/python3
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /tmp/python3 --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity",
 "raw_exe":"/tmp/python3","realpath":"/usr/bin/rm","sha256":"8e3faaa5..."}
execvp: Operation not permitted
exit=126

# Sprint 1 bypass 3 — PATH hijack
$ mkdir -p /tmp/hi && cp /bin/rm /tmp/hi/git
$ env PATH=/tmp/hi:$PATH ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json git --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity",
 "raw_exe":"/tmp/hi/git","realpath":"/tmp/hi/git","sha256":"8e3faaa5..."}
execvp: Operation not permitted
exit=126

# Hardlink probe
$ ln /bin/rm /tmp/hardgit
ln: failed to create hard link '/tmp/hardgit' => '/bin/rm': Operation not permitted
$ cp /bin/rm /tmp/myrm && ln /tmp/myrm /tmp/myalias_python3
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /tmp/myalias_python3 --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity",
 "realpath":"/tmp/myalias_python3","ino":213520176,"sha256":"8e3faaa5..."}
exit=126

# /proc/self/exe probe  -- realpath returns the SUPERVISOR binary, not the child's exe
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /proc/self/exe --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity",
 "raw_exe":"/proc/self/exe",
 "realpath":"/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard",
 "sha256":"40e156ab..."}
exit=126

# /proc/<child_pid>/exe (numeric) probe -- works correctly
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /usr/bin/python3 -c \
  'import os; pid=os.getpid(); os.execv(f"/proc/{pid}/exe", ["python3","--version"])'
{..."decision":"ALLOW",...}    # first execve of python3
{..."decision":"ALLOW","raw_exe":"/proc/3227899/exe","realpath":"/usr/bin/python3.12",...}
Python 3.12.3

# Symlink-flip TOCTOU probe (30 attempts, swap loop)
$ ln -sf /usr/bin/python3 /tmp/race/exe
$ (for i in $(seq 1 5000); do ln -sf /bin/rm /tmp/race/exe; ln -sf /usr/bin/python3 /tmp/race/exe; done) &
$ for i in $(seq 1 30); do ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /tmp/race/exe -c "print('python ran')"; done
# Result: every ALLOW resolved python3 and ran python; every BLOCK resolved rm. No mismatch caught in this brief test.
# Residual TOCTOU window between process_vm_readv and kernel re-resolve still exists; not weaponized here.

# Long-path / PATH_MAX edge (~2444 chars)
$ LONG2=$(python3 -c 'p="/tmp"; ...'); cp /usr/bin/python3 "$LONG2/python3"
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json "$LONG2/python3" --version
{...,"decision":"BLOCK","raw_exe":"/tmp/xxxx.../python3"...,"argv":["/tmp/xxxx (truncated to 512 bytes)","--version"]}
exit=126
# JSON validated by python3 json.loads -> ok=2 bad=0

# JSON injection via argv (quotes, newlines, backslashes)
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json '/tmp/a"b/git' 'x"y' $'a\nb' 'c\d'
{..."argv":["/tmp/a\"b/git","x\"y","a\nb","c\\d"]}
# json.loads -> OK; escaped values round-trip correctly

# Control chars and UTF-8
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /bin/rm $'\x01\x02\x03\x07' $'\x1f' $'\xc3\xa9'
# argv parsed: ['/bin/rm', '\x01\x02\x03\x07', '\x1f', 'é']

# Audit field completeness
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /usr/bin/git --version 2>/tmp/allow.json
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /bin/rm    --version 2>/tmp/block.json
# Promised fields: pid syscall raw_exe realpath cwd dev ino sha256 argv reason timestamp
# Result for ALLOW + BLOCK: MISSING from headline: set()      (i.e., all present)

# Policy file fail-open tests
$ ./bin/usernotify_exec_guard --policy /nonexistent.json /usr/bin/git --version
read policy: No such file or directory; exit=2
$ echo "{}" | (...)              # missing allowed_executables -> exit=2
$ echo '{"allowed_executables":[]}' (...)  # empty -> exit=2
$ echo "not json" (...)          # malformed -> exit=2
# All fail closed.

# Policy parser edge: policy_id with escaped quote breaks audit field
$ echo '{"policy_id":"contains \"allowed_executables\"","allowed_executables":["/usr/bin/git"]}' > /tmp/tricky.json
$ ./bin/usernotify_exec_guard --policy /tmp/tricky.json /usr/bin/git --version
{..."policy_id":"contains \\",...}    # truncated, but security still works

# Supervised child SIGKILL of supervisor
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /usr/bin/python3 -c \
  'import os, signal, time; os.kill(os.getppid(), signal.SIGKILL); time.sleep(0.5); os.execv("/bin/rm", ["rm","--version"])'
parent pid: 3227457
sent SIGKILL to ppid
OSError: [Errno 38] Function not implemented   # filter persists, listener orphaned, ENOSYS
exit=0   # exit reported by the harness's tee, not the supervisor

# Parallel execve concurrency
$ ./bin/usernotify_exec_guard --policy policy/sprint2.allow.json /bin/bash --noprofile --norc -c \
  'for i in 1 2 3 4 5 6 7 8 9 10; do /bin/rm --version 2>/dev/null & done; wait; echo done'
# ALLOW: 1 (bash); BLOCK: 10 (all rm calls); other: 1 (supervisor_exit)

# Cleanup
$ rm -rf /tmp/git /tmp/python3 /tmp/hi /tmp/myrm /tmp/myalias_python3 /tmp/race /tmp/confuse \
         /tmp/audit*.json /tmp/allow.json /tmp/block.json /tmp/parallel*.json \
         /tmp/{empty,no_allow,empty_allow,bad_json,badpath,relpath,tricky,tricky2,tricky3,tricky4,tricky5,tricky6,tricky7,tricky8,tricky9}*.json \
         /tmp/xxx[..long path..] '/tmp/a"b'
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint2_independent_review_b.md`
- Sprint 2 hardening memo: `proofs/SPRINT2_IDENTITY_HARDENING_20260430.md`
- Sprint 2 self-audit: `proofs/SPRINT2_AUDIT_20260430.md`
- Sprint 2 command log: `proofs/SPRINT2_COMMAND_LOG_20260430.md`
- Replay runs: `proofs/sprint2_runs/sprint2-20260430T220518Z` (preserved fail), `...20260430T220552Z`, `...20260430T220610Z`, `...20260430T220722Z` (pass=12), `...20260430T221125Z` (independent reproduction during this audit), `...20260430T221145Z` (this audit's reproduction)
- Guard source: `guard/usernotify_exec_guard.c` (672 lines, sha256 `58b8409d...`)
- Guard binary: `bin/usernotify_exec_guard` (sha256 `40e156ab...`)
- Policy file: `policy/sprint2.allow.json`
- Replay script: `scripts/replay_sprint2_identity.sh`
- Sprint 1 audit (prior context): `proofs/AUDIT_20260430_sprint1_independent_review.md`
