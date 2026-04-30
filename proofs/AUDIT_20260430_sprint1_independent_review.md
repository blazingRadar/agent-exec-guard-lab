# Sprint 1 — Independent Audit Review

Date: 2026-04-30
Auditor: independent third pass after the sprint's self-audit (`SPRINT1_AUDIT_20260430.md`)
Posture: adversarial review of the proof claims, with live re-derivation
Source of record: live commands run on this machine; SHAs re-derived; bypasses tested in front of the audit log

---

## Audit Question

Are the Sprint 1 claims in `SPRINT1_RAW_RUNTIME_BOUNDARY_20260430.md` and `SPRINT1_AUDIT_20260430.md` honest in shape and accurate in substance? And what should be tightened before Sprint 2 adds Docker?

## Verdict

**The engineering work is real. The posture (PARTIAL PASS, Docker BLOCKED, no overclaim) is correct.** But the security-shape framing of the proof understates two trivial bypass classes that an adversarial reader will find in five minutes. Tighten the claim before the work goes anywhere external.

The honest one-line summary should be:

> "A SECCOMP_RET_USER_NOTIF guard intercepts execve/execveat, applies a hardcoded **basename** allowlist, denies by default, and emits JSON audit records. The basename match is intentionally minimal; it is bypassable by trivial rename or symlink to a permitted basename. This is a Sprint 1 mechanism proof, not a security claim."

That sentence preserves what shipped and prevents misreading.

---

## What Verified Clean Independently

Re-derived from disk just now:

- Source SHA256: `8908182cde2cb877660ceeda27b9ff5ede496eac24cc7979236d89066deb8a95` ✓ matches sprint memo
- Binary SHA256: `29f80ef812a629189592afdb4fcca3c3a146a2ce70c82e20c79510f303cf6b8e` ✓ matches sprint memo
- Line count: 228 ✓ matches
- Filter intercepts execve and execveat on AUDIT_ARCH_X86_64 (BPF inspection)
- Non-x86_64 syscall arches fall through to `SECCOMP_RET_KILL_PROCESS` (terminal instr 7) — conservative, not a bypass
- `/bin/rm` blocked, exit 126: ✓ reproduced
- `/usr/bin/git` allowed, exit 0: ✓ reproduced
- JSON audit lines emitted on stderr: ✓ reproduced
- `PR_SET_NO_NEW_PRIVS` set before filter install (prevents setuid escalation): ✓ verified at line 49
- Supervisor poll/WNOHANG fix landed (prevents the documented hang): ✓ verified at lines 122–192

Discipline shape (Sprint 1 self-audit) is good:
- Pre-registered scope, in/out of scope explicit
- Failure honestly preserved (the supervisor-hang bug)
- Realism finding called out (locale-check helpers under non-clean shell startup)
- "Honest claim now allowed" / "Claims still not allowed" split is the right posture
- File timestamps + SHA256 anchoring give verifiable provenance

---

## Critical Finding 1 — Basename-only allowlist (severity: HIGH)

The allow check at `guard/usernotify_exec_guard.c:87-114` extracts the basename via `strrchr(path, '/')` and string-compares it against `bash, cat, echo, env, git, ls, python3, sh, true`. The audit log emits the *full path* but the *policy decision* uses only the basename.

**Live demonstration (this machine, just now):**

```
$ cp /bin/rm /tmp/git
$ ./bin/usernotify_exec_guard /tmp/git --version
{"decision":"ALLOW","reason":"allowed_executable","exe":"/tmp/git","policy":"sprint1_hardcoded_allowlist"}
rm (GNU coreutils) 9.4
exit=0
```

```
$ ln -sf /bin/rm /tmp/python3
$ ./bin/usernotify_exec_guard /tmp/python3 --version
{"decision":"ALLOW","reason":"allowed_executable","exe":"/tmp/python3","policy":"sprint1_hardcoded_allowlist"}
rm (GNU coreutils) 9.4
exit=0
```

Both runs allow `rm` by writing or symlinking it under a permitted basename. The audit log records `ALLOW exe=/tmp/git` and `ALLOW exe=/tmp/python3` — the trail does not flag that the policy was misled.

**Why this matters for the agent threat model.** The whole point of the guard is to bound an agent that may emit arbitrary shell commands. A bypass available to the agent is:

```
python3 -c "import shutil; shutil.copy('/bin/rm','/tmp/git')"
/tmp/git -rf /workspace
```

Step 1 invokes only Python, which is allowed; the file copy is open/read/write syscalls, not execve, so the guard is uninvolved. Step 2 invokes a binary whose basename is `git`, which the basename allowlist permits. The destructive operation runs, and the audit log shows two ALLOW decisions with no anomaly markers.

**Mitigation directions (any one closes the trivial case):**
- Match by absolute realpath against an allowlist of fully-qualified paths.
- Stat the resolved exe and compare device+inode against a known set, not by name.
- Validate by FD: have the guard open the target via `O_PATH`, fstat, then re-exec via `execveat` against a validated FD.
- At minimum: reject any path not under a small set of approved prefixes (`/usr/bin/`, `/bin/`, `/usr/local/bin/`).

The fix is not architectural; it is one function. Do it before Sprint 2.

---

## Critical Finding 2 — `SECCOMP_USER_NOTIF_FLAG_CONTINUE` on a path-validating policy (severity: HIGH)

Line 180 sets `resp.flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE` on the ALLOW path. This tells the kernel to re-execute the original syscall as if the filter weren't there — including re-reading the path string from userspace memory.

This is the well-known seccomp user-notify TOCTOU pattern. Linux kernel docs (`man 2 seccomp_unotify`, "TOCTOU considerations") explicitly warn against using `CONTINUE` for path-validating policies because:

1. Supervisor reads path P1 from child memory via `process_vm_readv` → matches allowlist
2. Supervisor sends `CONTINUE` response
3. Before the kernel re-runs the syscall, the child rewrites the same memory to point at path P2 (e.g., `/bin/rm`)
4. Kernel re-reads from userspace, calls `execve(P2)`, P2 runs

The mitigation pattern documented in the kernel headers is to either:
- Never CONTINUE; instead, validate, then deny or redirect via `SECCOMP_IOCTL_NOTIF_ADDFD` to inject a validated FD into the child and synthesize the syscall yourself.
- Or use `execveat` against an FD that the supervisor itself validated, so userspace memory mutation can't change which file gets executed.

This finding is theoretical against an in-process Python attacker who doesn't already know the supervisor uses CONTINUE — but it's well-documented and a reviewer with seccomp experience will name it on first read. Treat it as a known-flaw-with-mitigation rather than a surprise. Document it as such, then close it in Sprint 2 or Sprint 3 by switching to FD-anchored validation.

---

## Secondary Finding 1 — Audit log doesn't record what was actually executed when basename was misled

When the basename matches, the audit log records the path the supervisor saw at notification time. After CONTINUE, the kernel re-reads userspace; if the path was swapped (Critical Finding 2), the actually-executed binary differs from the logged one. Even without TOCTOU, the basename bypass (Critical Finding 1) means the log records `ALLOW /tmp/git` while the binary on disk at `/tmp/git` may be a copy of `/bin/rm`. The log is faithful to "what the supervisor decided"; it is not faithful to "what ran."

**Mitigation:** add `realpath` + sha256 of the resolved file (or device+inode) to the audit record. That way the trail captures the binary identity, not just the requested name.

---

## Secondary Finding 2 — JSON audit record is missing fields the candidate's own discipline standard would require

Compare the audit record format here:

```
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
```

…against what other audit memos in this lab already capture (timestamp, pid, parent pid, source, byte-identical inputs). Missing here:

- `timestamp` (RFC3339 or epoch_ns)
- `pid` of the child being supervised
- `ppid` (parent pid — important for nested subprocess attribution)
- `argv` — the full argv vector, not just `argv[0]`
- `cwd` — child's working directory at notification time
- `audit_id` — monotonic counter for ordering across processes

`pid` and `argv` matter most. Without `pid` you cannot reconstruct nested chains in concurrent runs; without `argv` you lose the actual command being launched (e.g., `rm -rf /workspace` vs `rm --version`).

These are one-evening additions and they bring the JSON in line with the lab's existing audit-trail convention.

---

## Secondary Finding 3 — Shell builtins aren't covered (informational, not a bypass)

`./bin/usernotify_exec_guard /bin/bash --noprofile --norc -c 'echo hi; type echo'` runs without a second BLOCK or ALLOW record after bash itself, because `echo` is a shell builtin and bash never calls execve for it. This is the correct behavior of seccomp on execve filters, not a flaw — but it's worth recording: the guard sees process boundaries, not shell-internal command boundaries. Anything bash, sh, or python implements internally is invisible. Document this in the threat model so a reviewer doesn't expect file-write coverage from an execve filter.

---

## Secondary Finding 4 — No supervisor exit-summary record

The JSON stream is per-decision. There's no closing record like `{"event":"supervisor_exit","child_status":126,"decisions":3,"allow":1,"block":2}`. For machine-readable audit replay, the absence of a closing record means a downstream parser can't tell whether the supervisor exited cleanly or was killed mid-stream. Add a single supervisor-exit JSON line on shutdown.

---

## Secondary Finding 5 — Hardcoded allowlist in C source

The allowlist lives at `guard/usernotify_exec_guard.c:95-105`. Sprint 2 will need a policy file format anyway (Docker integration implies parameterized policy). The current hardcoded form is appropriate for Sprint 1 mechanism proof; flag it explicitly as "policy is hardcoded and not yet parameterizable" rather than letting it be implicit. Sprint 2 should land a `policy.json` schema with allowlist + denylist + default-deny semantics.

---

## What This Audit Does Not Find

- The supervisor-hang fix (poll + WNOHANG) is correctly placed and works.
- `PR_SET_NO_NEW_PRIVS` is correctly set before filter install (prevents setuid escalation through allowed binaries).
- Architecture handling is conservative (non-x86_64 → KILL_PROCESS, not ALLOW). This restricts 32-bit syscall use but doesn't bypass the policy.
- The discipline shape (sprint memo + audit memo + command log + scope statement + claims-not-allowed list) is exactly the convention that earned the claim detector its credibility. Keep doing this on every sprint.

---

## Honest Claim That Should Replace the Sprint 1 Headline

Current claim (in `SPRINT1_AUDIT_20260430.md` and the sprint memo):

> "A raw local seccomp user-notify guard can enforce below-process-launch policy on this machine: it allows approved developer commands, blocks `/bin/rm`, blocks nested subprocess attempts, and emits JSON audit records."

Tightened claim that survives adversarial review:

> "A raw local SECCOMP_RET_USER_NOTIF supervisor on this machine intercepts every `execve`/`execveat` from a supervised child, applies a hardcoded **basename** allowlist (`bash, cat, echo, env, git, ls, python3, sh, true`), denies by default with `EPERM`, and emits one JSON decision record per call. The mechanism is verified end-to-end: blocking `/bin/rm` directly, blocking `/bin/rm` invoked from an allowed Python child, and blocking `/bin/rm` invoked from an allowed bash child. The basename allowlist is intentionally minimal and is bypassable by trivial rename or symlink to a permitted basename; the supervisor uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE` on allow, which carries a known TOCTOU window between the policy decision and the kernel re-read of userspace path arguments. Sprint 1 proves the boundary mechanism, not a security boundary."

The hardening (realpath/FD-anchored policy, addfd-style synthesized exec, richer audit fields) is Sprint 2/3 work. Naming the gap now keeps the trail honest.

---

## Sprint 2 Prerequisites (audit-derived)

Before adding Docker / OpenHands work in Sprint 2, this audit recommends closing in this order:

1. **Replace basename match with absolute-realpath match** (or device+inode match). One function. Closes Critical Finding 1.
2. **Add `pid`, `argv`, `timestamp`, `cwd`, `realpath`, and `sha256` to the JSON audit record.** Closes Secondary Findings 1 and 2.
3. **Decide and document the TOCTOU posture.** Either (a) switch the ALLOW path off `CONTINUE` to an `addfd`-anchored re-emit, or (b) document the residual TOCTOU explicitly in the README threat model. (a) is the production fix; (b) is acceptable for a Sprint 2 demo as long as it's named.
4. **Externalize the policy into `policy.json`** with allowlist, denylist, and default-deny semantics.
5. **Add a supervisor-exit JSON record** so audit replay parsers have a stream terminator.

After (1)–(5), then Docker. Not before. Adding Docker on top of a basename-bypass policy makes the demo *worse* because reviewers will assume the container layer shoulders security weight that the guard doesn't carry.

---

## Discipline Observations (worth preserving)

What the candidate did right that should be preserved as the convention for every sprint going forward:

- Re-derivable provenance (source SHA + binary SHA + line count) — let me verify the work without rebuilding it.
- Pre-registered scope (in/out of scope sections) — keeps the claim narrow on purpose.
- Honest preservation of the supervisor-hang failure rather than rewriting it out.
- Explicit "Claims Still Not Allowed" list — prevents the sprint from being misread as more than it is.
- Realism finding (locale-check helpers under non-clean shell startup) — shows engineering instinct, not just mechanism delivery.
- Per-file timestamps in the proof memo, command log, and audit memo — separates evidence from interpretation.

This is the same discipline that earned the claim detector's audit chain its credibility. It is the candidate's actual differentiator and it is real.

---

## Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

sha256sum guard/usernotify_exec_guard.c
  -> 8908182cde2cb877660ceeda27b9ff5ede496eac24cc7979236d89066deb8a95  guard/usernotify_exec_guard.c
sha256sum bin/usernotify_exec_guard
  -> 29f80ef812a629189592afdb4fcca3c3a146a2ce70c82e20c79510f303cf6b8e  bin/usernotify_exec_guard
wc -l guard/usernotify_exec_guard.c
  -> 228 guard/usernotify_exec_guard.c

timeout 5 ./bin/usernotify_exec_guard /bin/rm --version
  -> {"decision":"BLOCK",...,"exe":"/bin/rm",...}; execvp: Operation not permitted; exit=126

timeout 5 ./bin/usernotify_exec_guard /usr/bin/git --version
  -> {"decision":"ALLOW",...,"exe":"/usr/bin/git",...}; git version 2.43.0; exit=0

# Bypass test 1 — basename collision via copy
cp /bin/rm /tmp/git
timeout 5 ./bin/usernotify_exec_guard /tmp/git --version
  -> {"decision":"ALLOW",...,"exe":"/tmp/git",...}; rm (GNU coreutils) 9.4 ...; exit=0

# Bypass test 2 — basename collision via symlink
ln -sf /bin/rm /tmp/python3
timeout 5 ./bin/usernotify_exec_guard /tmp/python3 --version
  -> {"decision":"ALLOW",...,"exe":"/tmp/python3",...}; rm (GNU coreutils) 9.4 ...; exit=0

# Cleanup
rm -f /tmp/git /tmp/python3
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint1_independent_review.md`
- Sprint 1 memo: `proofs/SPRINT1_RAW_RUNTIME_BOUNDARY_20260430.md`
- Sprint 1 self-audit: `proofs/SPRINT1_AUDIT_20260430.md`
- Sprint 1 command log: `proofs/SPRINT1_COMMAND_LOG_20260430.md`
- Guard source: `guard/usernotify_exec_guard.c`
- Guard binary: `bin/usernotify_exec_guard`
