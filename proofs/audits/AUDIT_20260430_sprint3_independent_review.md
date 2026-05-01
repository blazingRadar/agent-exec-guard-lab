# Sprint 3 — Independent Audit Review

Date: 2026-04-30
Auditor: orchestrator (third independent pass after Sprint 3 self-audit `SPRINT3_LANDLOCK_UNDERLAY_20260430.md`).
Posture: adversarial review, with live re-derivation; specifically checks both (a) the new Landlock work and (b) whether the Sprint 2 audit-integrity prerequisites that the Sprint 3 fix-path analysis named as ship-in-Sprint-3-unconditionally actually shipped.
Source of record: live commands run on this machine; SHAs re-derived; bypasses re-tested.

---

## Audit Question

Did Sprint 3 (a) deliver the Landlock execute-underlay claim it makes, (b) close or carry forward the Sprint 2 audit-integrity findings that the fix-path analysis flagged as Sprint 3 prerequisites independent of the C₁ work, and (c) leave the "Claims Still Not Allowed" list complete and honest with respect to what was *not* changed?

## Verdict

**Sprint 3's Landlock work is real, lands cleanly, and is worth keeping.** The probes verify, the replay passes, the source compiles with `-Wall -Wextra -fanalyzer` clean, and the new layer materially reduces the post-decision filesystem-swap surface as claimed.

**However**, the Sprint 3 fix-path analysis (`SPRINT3_FIX_PATH_ANALYSIS_A_20260430.md`, `SPRINT3_FIX_PATH_ANALYSIS_B_20260430.md`) explicitly named six Sprint 2 audit-integrity prerequisites that ship "in Sprint 3 unconditionally — independent of C₁." Live regression on the Sprint 3 binary shows **none of the six landed**. Three of them are HIGH or HIGH-equivalent findings reproducible against the current build:

- audit log can still be forged by the supervised child
- supervisor can still be silently killed by the child with no `supervisor_exit` record
- policy parser still has a fail-open path on a structurally malformed `allowed_executables`

The Sprint 3 self-audit's "Claims Still Not Allowed" list grew with Landlock-specific carve-outs (no read/write/network coverage, etc.) but did **not** carry forward the unclosed Sprint 2 findings. That is a delivery and disclosure gap, not a mechanism gap.

The honest one-line summary of Sprint 3's actual state:

> "Sprint 3 adds a child-inherited Landlock execute underlay that, on this kernel, denies execution of non-policy files even after `F_CONT` resumes a path-based syscall, while preserving the Sprint 2 replay (pass=12, fail=0). The Sprint 2 critical findings on audit-trail integrity (forgeable audit stream, killable supervisor, fail-open policy-parser walk, `/proc/self/exe` resolved in supervisor namespace, fork+exec to `/usr/bin/sha256sum`, silent argv truncation) all remain open; they were named as Sprint 3 prerequisites by the fix-path analysis but did not land."

Recommend: Sprint 3's Landlock work is **kept**. Sprint 4 must close the carry-forwards before any external claim or Docker work.

---

## What Verified Clean Independently

Re-derived from disk and re-run live:

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
ff540da83e4b7f2a55d3535f08d038dc78e7be7c0cdb2a1844beb761d4461bd3  guard/usernotify_exec_guard.c
ab53dfb1e5235fcff5d782b21bb5910a6c2c0cb997d102731428173536369b94  bin/usernotify_exec_guard
$ wc -l guard/usernotify_exec_guard.c
793 guard/usernotify_exec_guard.c
```

Both SHAs match the claimed values in `SPRINT3_LANDLOCK_UNDERLAY_20260430.md`. Source grew from 672 (Sprint 2) to 793 lines (Sprint 3) — +121 lines, consistent with the claimed Landlock additions.

Landlock ABI on host (kernel 6.17), live-probed via direct syscall:

```
$ python3 -c "import ctypes; libc = ctypes.CDLL(None, use_errno=True); rc = libc.syscall(444, 0, 0, 1); print('landlock_create_ruleset(NULL,0,1)=', rc); print('errno=', ctypes.get_errno())"
landlock_create_ruleset(NULL,0,1)= 7
errno= 0
```

ABI 7 confirmed. Matches Sprint 3 self-audit.

Sprint 2 replay re-ran from scratch on Sprint 3 binary:

```
$ bash scripts/replay_sprint2_identity.sh
PASS compile gcc clean
PASS allow_git ... PASS direct_block_rm ... PASS bash_nested_block_rm ...
PASS python_nested_block_rm ... PASS copy_rename_bypass_blocked ...
PASS symlink_bypass_blocked ... PASS env_path_bypass_blocked ...
PASS json_escape_hostile_path ... PASS execveat_blocked
pass=12 fail=0
```

Sprint 1 basename bypass against Sprint 3 binary — still blocked:

```
$ cp /bin/rm /tmp/git
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/git --version
{...,"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/tmp/git","realpath":"/tmp/git","sha256":"8e3faaa5...",...}
exit=126
```

Hardlink-at-non-allowed-path (Landlock-specific edge probe) — correctly blocked:

```
$ cp /bin/bash /tmp/bashcopy && ln /tmp/bashcopy /tmp/bashalias
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/bashalias -c 'echo hi'
{...,"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/tmp/bashalias","realpath":"/tmp/bashalias",...}
exit=126
```

Confirms that even though Linux hardlink shares the inode with the source, Landlock's path-beneath rules and Γ's realpath check both reject `/tmp/bashalias` because neither matches an allowlist entry.

The three Sprint 3 probes (`landlock_file_exec_probe`, `landlock_dynamic_exec_probe`, `landlock_replace_path_probe`) are present in `proofs/sprint3_scratch/` with their `.exit`, `.stdout`, `.stderr` outputs preserved. Output sentinels `RESULT file_level_execute_rule=PASS`, `RESULT dynamic_exact_execute_rules=PASS`, `RESULT replacement_path_exec_denied=PASS` are reproducible.

Failed-run preservation discipline: nothing failed during Sprint 3 work, so there's nothing to preserve, but the existing Sprint 2 failed run at `proofs/sprint2_runs/sprint2-20260430T220518Z` was not deleted or rewritten. Discipline preserved.

`gcc -Wall -Wextra -fanalyzer` claim: re-verified via the command log; `-fanalyzer` is more demanding than `-Wall -Wextra` and producing no diagnostics on a 793-line C file is non-trivial. Credit.

The Landlock claim itself — "Seccomp decides; Landlock enforces the executable universe underneath it" — is accurate against the current source and probes.

---

## Critical Observation — Sprint 2 audit-integrity findings did not ship in Sprint 3

The Sprint 3 fix-path analysis (which the user themselves commissioned, read, and acted on for the Landlock decision) explicitly stated that six Sprint 2 audit-integrity prerequisites should ship in Sprint 3 **unconditionally and independently of C₁**. Quoting Auditor A's headline verbatim:

> "the Sprint 2 audit-integrity prerequisites (audit fd separation, SIGTERM handler, real JSON parser, child-anchored realpath, inline SHA256, argv_truncated) ship in Sprint 3 unconditionally — they are independent of C₁ and the audit chain has flagged them as load-bearing."

Auditor B's headline matched: "The Sprint 2 audit-stream-forgery and killable-supervisor findings are unaffected by Φ_A and remain on the Claims Still Not Allowed list."

Verified via `grep` against the current Sprint 3 source — none of the six landed:

| Sprint 2 finding | Recommended Sprint 3 fix | Status in current `usernotify_exec_guard.c` |
|---|---|---|
| Audit stream shared with child stderr (CF1, HIGH) | Open dedicated supervisor audit fd before `fork()` | `fprintf(stderr, ...)` at line 624 — still shared |
| Supervisor killable by child (CF2, HIGH) | SIGTERM/INT/HUP handler emitting final `supervisor_exit{reason=killed_by_signal}` | grep for `signal\|sigaction\|SIGTERM\|killed_by_signal` returns 0 hits — no handler |
| `strstr`-based policy parser fail-open (S1/S2) | Replace with real JSON library (jansson, json-c, vendored) | Lines 346-376 still walk `strstr`/`strchr` over the file buffer |
| `/proc/self/exe` resolves in supervisor namespace | Resolve via `/proc/<child_pid>/exe` | grep for `/proc/.*pid.*exe`, `/proc/%d/exe` returns 0 hits |
| `file_sha256` fork+execs `/usr/bin/sha256sum` (S5) | Inline SHA256 (libcrypto/libsodium/picohash) | Line 261: `execl("/usr/bin/sha256sum", ...)` unchanged |
| argv per-arg cap silent at 512 bytes, 8 args | Add `argv_truncated`/`argv_total_count` JSON fields | grep for `truncated` returns 0 hits; `MAX_ARGV_CAPTURE = 8` at line 50 unchanged |

Sprint 3's "Claims Still Not Allowed" list grew with Landlock-specific carve-outs (no read/write/network coverage, no `execveat` support, no fd-stable execution) but did **not** carry forward the unclosed Sprint 2 findings. The list reads as if Sprint 2 was clean before Sprint 3 started; it wasn't.

This is the same pattern the lab's earlier audit work caught in other projects: a sprint adds a real new layer, the new layer's caveats get listed, but the prior sprint's open findings silently fall off the disclosure register. The candidate's own discipline says "audit memos are load-bearing institutional memory" — this is the carry-forward gap that discipline is designed to catch.

---

## Live Regressions — Sprint 2 critical findings reproduced against Sprint 3 binary

Each of these was demonstrated against `bin/usernotify_exec_guard` SHA `ab53dfb1...` (the Sprint 3 build) just now.

### Regression 1 — Audit log forgery via shared stderr (Sprint 2 A's CF1, HIGH)

```
$ timeout 5 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import sys
sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_IN_SPRINT3\"}\n")
sys.stderr.flush()'
```

Captured stream:

```
{"event":"exec_decision",...,"raw_exe":"/usr/bin/python3","decision":"ALLOW",...,"reason":"allowed_executable_identity"...}
{"event":"exec_decision","decision":"ALLOW","raw_exe":"/bin/rm","reason":"FORGED_IN_SPRINT3"}
{"event":"supervisor_exit",...}
```

The forged middle record was emitted by the supervised Python child writing to its own stderr, which is fd 2, which is the same fd the supervisor uses for its audit JSON. From a downstream `python3 -c "import json; [json.loads(l) for l in sys.stdin]"` parser, the forged record is indistinguishable from a real supervisor decision. **Unchanged from Sprint 2.**

### Regression 2 — Supervisor killable by child via SIGTERM (Sprint 2 A's CF2, HIGH)

```
$ timeout 8 ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c '
import os, signal, time
ppid = os.getppid()
print("BEFORE pid=%d ppid=%d" % (os.getpid(), ppid), flush=True)
os.kill(ppid, signal.SIGTERM)
time.sleep(0.3)
print("AFTER kill survived", flush=True)
'
```

Output:

```
{...,"decision":"ALLOW","raw_exe":"/usr/bin/python3",...}
BEFORE pid=3237762 ppid=3237752
Terminated
exit=143
```

Supervisor died (SIGTERM, exit 128+15=143). No `supervisor_exit` JSON record was emitted. The "AFTER kill survived" line never printed because the shell tee was terminated alongside. The audit stream is silently truncated. **Unchanged from Sprint 2.**

Note one bright spot: although the supervisor died, the seccomp filter the child installed for itself persists — so the child cannot escape *to do new exec-class operations* even after killing the supervisor. The Sprint 2 "Auditor B" framing (fail-safe at the kernel level) is correct for the security invariant. The Sprint 2 "Auditor A" framing (load-bearing for audit-trail integrity) is also correct. Both are reaffirmed in Sprint 3.

### Regression 3 — Policy parser walks past string-valued `allowed_executables` (Sprint 2 A's parser fail-open)

```
$ cat > /tmp/spoof_s3.policy.json <<'EOF'
{ "policy_id": "spoof",
  "allowed_executables": "should_be_array",
  "extra": [ "/bin/echo" ],
  "more_paths": [ "/bin/rm" ] }
EOF
$ ./bin/usernotify_exec_guard --policy /tmp/spoof_s3.policy.json /bin/echo SPRINT3_SPOOF_TEST
{...,"policy_id":"spoof","decision":"ALLOW","reason":"allowed_executable_identity","raw_exe":"/bin/echo",...}
SPRINT3_SPOOF_TEST
{"event":"supervisor_exit",...,"child_exit":0}
exit=0
```

The policy declares `"allowed_executables": "should_be_array"` (a string, not an array). The parser silently walks forward through the file looking for the next `[…]` block, finds `"extra": [ "/bin/echo" ]`, treats it as the allowlist, and ALLOWs `/bin/echo`. **Unchanged from Sprint 2.** A future operator who writes a policy with a non-array `allowed_executables` value adjacent to any other `[…]` block can land in this fail-open mode.

### Regression 4 — `/proc/self/exe` resolves in supervisor namespace (Sprint 2 S2, audit-fidelity)

```
$ ./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /proc/self/exe --version
{...,"raw_exe":"/proc/self/exe","realpath":"/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard","sha256":"ab53dfb1...","decision":"BLOCK"...}
exit=126
```

The supervisor resolved `/proc/self/exe` in its own process context, so the recorded `realpath` is the supervisor's own binary, not the child's actual executable. Currently fail-closed (the supervisor binary isn't on the allowlist), but the audit log lies about what the child tried to exec. **Unchanged from Sprint 2.**

---

## What This Audit Does Find Genuinely New for Sprint 3

The Landlock additions introduce no new bypass classes I could produce. Specifically:

- Hardlink at a non-allowed path: BLOCKed by Γ realpath check (the realpath of `/tmp/bashalias` is itself, not `/bin/bash`). Live-confirmed above.
- Symlink at a non-allowed path to an allowed binary: was already blocked by Sprint 2 logic; Landlock would also block at exec time because the path used in execve is not under any path-beneath rule.
- `/proc/self/exe`: BLOCKed by Sprint 2 realpath logic *before* Landlock matters. Landlock would also block (the supervisor's own binary is not under any allowed path). Composition is fail-closed.
- Sprint 1 basename bypass: BLOCKed at the Sprint 2 layer; Landlock provides the second wall.

Sprint 3's claim that Landlock denies a *post-F_CONT* swap of the resolved path is supported by `landlock_replace_path_probe` (preserved at `proofs/sprint3_scratch/landlock_replace_path_probe.{c,exit,stderr,stdout}`). I did not independently re-construct a TOCTOU race-window experiment in this audit (the Sprint 2 A audit already exercised that and produced inconsistent audit records but no clean bypass). The probe is structurally sound and reproducible.

---

## Honest Claim That Should Replace the Sprint 3 Headline

Current claim (`SPRINT3_LANDLOCK_UNDERLAY_20260430.md` "Claim Now Allowed"):

> "A local seccomp user-notify execution guard can preserve Sprint 2 file-backed executable identity checks while adding a child-inherited Landlock execute underlay. On this host, the underlay grants execute to exact policy executable files plus the dynamic loader, denies copied non-policy executables, and denies a replaced executable at a previously allowed pathname. The existing 12-case Sprint 2 replay still passes."

This is accurate as written for what Sprint 3 *added*. It is incomplete because it does not name what Sprint 3 *did not change*.

Tightened claim that survives this audit:

> "Sprint 3 adds a child-inherited Landlock execute underlay (kernel 6.17, ABI 7) to the existing Sprint 2 supervisor architecture. The underlay grants `LANDLOCK_ACCESS_FS_EXECUTE` to exact policy executable files plus the dynamic loader, denies copied non-policy executables, and denies a replaced executable at a previously allowed pathname; the 12-case Sprint 2 replay still passes (pass=12, fail=0). The honest framing is 'seccomp decides; Landlock enforces the executable universe underneath it.' Sprint 3 does not address the Sprint 2 audit-integrity findings: the audit stream is still on fd 2 and forgeable by the supervised child; the supervisor is still killable by the child via `kill(getppid(), SIGTERM)` with no `supervisor_exit` record on the way out; the `strstr`-based policy parser still has a fail-open path on a structurally malformed `allowed_executables`; `/proc/self/exe` still resolves in the supervisor's namespace; SHA256 still requires fork+exec to `/usr/bin/sha256sum`; and argv capture still truncates silently at 512 bytes per arg / 8 args total. Sprint 3 is a strong Landlock-layer addition with the Sprint 2 audit-integrity prerequisites carried forward."

---

## Sprint 4 Prerequisites (audit-derived)

Carry-forward items from Sprint 2 that the fix-path analysis named as Sprint 3 prerequisites and that did not land:

1. **Separate the audit stream from child stderr.** Open a dedicated O_CLOEXEC supervisor-only fd before `fork()`; route child stderr to a separate file or pipe. Closes Sprint 2 A's CF1.
2. **SIGTERM/INT/HUP handler in the supervisor.** Install before `fork()`; emit `supervisor_exit{reason=killed_by_signal}` and flush before exit. Closes Sprint 2 A's CF2.
3. **Replace `strstr` policy parsing with a real JSON parser.** Closes both auditors' S1/S2.
4. **Anchor `realpath` resolution in child filesystem context.** Use `/proc/<child_pid>/exe` for `/proc/self/exe`; consider `/proc/<child_pid>/root/...` for the general case. Closes both auditors' /proc/self/exe finding.
5. **Inline SHA256.** Drop fork+exec to `/usr/bin/sha256sum`. Closes Sprint 2 A's S5.
6. **Add `argv_truncated`/`argv_total_count` to JSON when capture truncates.** Closes both auditors' argv-truncation finding.

Then, *after* (1)–(6):

7. Decide CONTINUE TOCTOU posture for production framing. The Landlock layer materially reduces the practical exploitability of a path-swap-after-decision attack, but does not eliminate it for swaps to other allowed binaries (a child could swap `/usr/bin/git` to `/usr/bin/python3` mid-syscall and Landlock would still allow exec — both are in Π_exec). Document explicitly. Φ_B (`SECCOMP_IOCTL_NOTIF_ADDFD`) remains the architectural fix if needed.

8. Sprint 4 should also extend `policy/sprint2.allow.json` schema to optionally include explicit Landlock anchors (path-beneath base directories vs. exact-file rules), so the operator can choose tightness vs. portability without recompiling the guard.

After (1)–(6), Docker may be on the table for Sprint 5.

---

## Discipline Observations

What's preserved between Sprint 2 and Sprint 3:

- Re-derivable provenance (SHAs match across self-audit, command log, replay run; new probe sources also hashed).
- Per-probe artifact preservation (each probe's `.c`, binary, `.exit`, `.stdout`, `.stderr` saved under `proofs/sprint3_scratch/`).
- Lab-local scratch (no `/tmp` artifacts in proof tree).
- Sprint 2 failed-run preservation (`sprint2-20260430T220518Z`) untouched.
- `-fanalyzer` clean compile is a non-trivial discipline addition; preserve it as a pre-commit gate.

What slipped between Sprint 2 and Sprint 3:

- The carry-forward of unclosed Sprint 2 findings into Sprint 3's "Claims Still Not Allowed" list. The Sprint 3 list grew with Landlock-specific items but did not retain the Sprint 2 audit-integrity items as still-open. The fix-path analysis specifically warned this would happen.
- The Sprint 3 self-audit cites the fix-path analysis as the planning input but does not list the audit-integrity prerequisites as explicit Sprint 3 deliverables (delivered or deferred). A short "Carry-forward open items from Sprint 2" section in the proof memo would have made the gap explicit.

The pattern to keep going forward: every sprint memo should lead with a **"Carry-forward Open Items"** section listing all unclosed findings from the prior sprint by name and current status (closed-this-sprint / deferred-to-next / declared-out-of-scope). That mirrors the existing claim detector's audit-trail discipline (where pre-Sprint-4 baselines were preserved with explicit `artifact_status` markers).

---

## Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

# Re-derive provenance
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
  -> ff540da83e4b7f2a55d3535f08d038dc78e7be7c0cdb2a1844beb761d4461bd3  guard/usernotify_exec_guard.c
  -> ab53dfb1e5235fcff5d782b21bb5910a6c2c0cb997d102731428173536369b94  bin/usernotify_exec_guard
wc -l guard/usernotify_exec_guard.c
  -> 793 guard/usernotify_exec_guard.c

# Live Landlock ABI probe (kernel 6.17 → ABI 7 confirmed)
python3 -c "import ctypes; libc = ctypes.CDLL(None, use_errno=True); rc = libc.syscall(444, 0, 0, 1); print(rc, ctypes.get_errno())"
  -> 7 0

# Replay reruns clean against Sprint 3 binary
bash scripts/replay_sprint2_identity.sh
  -> pass=12 fail=0  run_root=proofs/sprint2_runs/sprint2-20260430T231136Z

# Sprint 1 basename bypass — still BLOCKED
cp /bin/rm /tmp/git
./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/git --version
  -> BLOCK reason=blocked_executable_identity exit=126

# Hardlink-at-non-allowed-path probe
cp /bin/bash /tmp/bashcopy && ln /tmp/bashcopy /tmp/bashalias
./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /tmp/bashalias -c 'echo hi'
  -> BLOCK realpath=/tmp/bashalias exit=126

# Audit forgery (Sprint 2 A's CF1) — STILL WORKS
./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import sys; sys.stderr.write("\n{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_IN_SPRINT3\"}\n")'
  -> Forged JSON record present in stream alongside real supervisor records

# Supervisor kill (Sprint 2 A's CF2) — STILL WORKS
./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /usr/bin/python3 -c \
  'import os, signal, time; os.kill(os.getppid(), signal.SIGTERM); time.sleep(0.3)'
  -> exit=143 (supervisor SIGTERM); no supervisor_exit JSON record emitted

# Policy parser fail-open (Sprint 2 A's parser walk) — STILL WORKS
echo '{"policy_id":"spoof","allowed_executables":"should_be_array","extra":["/bin/echo"],"more_paths":["/bin/rm"]}' > /tmp/spoof_s3.policy.json
./bin/usernotify_exec_guard --policy /tmp/spoof_s3.policy.json /bin/echo SPRINT3_SPOOF_TEST
  -> ALLOW /bin/echo (parser walked past string-valued allowed_executables to next [...] block)

# /proc/self/exe namespace bug — STILL WORKS
./bin/usernotify_exec_guard --policy ./policy/sprint2.allow.json /proc/self/exe --version
  -> realpath=/home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard (supervisor's own binary)

# grep audit-integrity gaps in source
grep -n "fprintf(stderr" guard/usernotify_exec_guard.c | wc -l
  -> 8 (audit and error paths still on stderr)
grep -nE "signal\(|sigaction|SIGTERM|killed_by_signal" guard/usernotify_exec_guard.c
  -> (no hits)
grep -nE "strstr|strchr" guard/usernotify_exec_guard.c | head -5
  -> 346:strstr(buf, "\"policy_id\""), 357:strstr(buf, "\"allowed_executables\""), ...
grep -nE "/proc/.*pid.*exe|/proc/%d/exe" guard/usernotify_exec_guard.c
  -> (no hits)
grep -nE "sha256sum|SHA256_|EVP_sha256|picohash" guard/usernotify_exec_guard.c
  -> 261:execl("/usr/bin/sha256sum", ...)
grep -nE "argv_truncated|truncated" guard/usernotify_exec_guard.c
  -> (no hits)

# Cleanup
rm -f /tmp/git /tmp/bashcopy /tmp/bashalias /tmp/spoof_s3.policy.json
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint3_independent_review.md`
- Sprint 3 proof memo: `proofs/SPRINT3_LANDLOCK_UNDERLAY_20260430.md`
- Sprint 3 command log: `proofs/SPRINT3_COMMAND_LOG_20260430.md`
- Sprint 3 fix-path analyses: `proofs/SPRINT3_FIX_PATH_ANALYSIS_A_20260430.md`, `proofs/SPRINT3_FIX_PATH_ANALYSIS_B_20260430.md`
- Sprint 3 probe artifacts: `proofs/sprint3_scratch/landlock_*_probe.{c,exit,stderr,stdout}`
- Sprint 2 prior audits: `proofs/AUDIT_20260430_sprint2_independent_review_a.md`, `proofs/AUDIT_20260430_sprint2_independent_review_b.md`
- Sprint 1 prior audit: `proofs/AUDIT_20260430_sprint1_independent_review.md`
- Source: `guard/usernotify_exec_guard.c` (793 lines, sha256 ff540da8…)
- Binary: `bin/usernotify_exec_guard` (sha256 ab53dfb1…)
