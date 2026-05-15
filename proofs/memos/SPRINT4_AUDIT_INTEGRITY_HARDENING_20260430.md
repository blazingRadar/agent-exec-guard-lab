# Sprint 4 Audit Integrity Hardening

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: close Sprint 2 carry-forward audit findings before Docker/OpenHands.

## Carry-Forward Open Items

| ID | Finding | Sprint 4 status |
|---|---|---|
| F1 | Audit log forgery via shared fd 2 | Closed this sprint. Child stderr is routed through a pipe and emitted as escaped `child_stderr` records; supervisor audit writes to a duplicated supervisor-only fd. |
| F2 | Supervisor killable by child with no final record | Closed for SIGTERM/INT/HUP. Handler emits `supervisor_exit{reason:killed_by_signal}` before exit. This is still denial-of-service, not survival. |
| F3 | Policy parser fail-open on malformed `allowed_executables` | Closed for reproduced class. The parser now validates the root object and requires `allowed_executables` to be an array of absolute strings. |
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred. Sprint 3 Landlock reduces practical non-policy executable execution, but fd-stable execution remains Sprint 5+ architecture work. |
| F5 | `/proc/self/exe` resolves in supervisor context | Closed for reproduced nested child case. `/proc/self/...` is rewritten to numeric `/proc/<child_pid>/...`; absolute paths resolve through `/proc/<pid>/root`. |
| F6 | `file_sha256` fork+execs `/usr/bin/sha256sum` | Closed. SHA256 is computed in-process via Linux AF_ALG. |
| F7 | argv silently truncates | Closed. Audit records include `argv_truncated` and `argv_total_count`. |
| F8 | escaped quote in `policy_id` corrupts provenance | Closed with F3 parser replacement for the policy schema. |
| A1 | JSON parser deep nesting DoS | Closed in sweep. Unknown JSON values are skipped with `MAX_JSON_DEPTH=64`; reproduced 80-deep policy is rejected. |
| A2 | `argv_total_count` saturates at scan cap without disclosure | Closed in sweep. Audit records now include `argv_total_count_capped`. |
| A3 | `child_stderr` embedded NUL hides trailing bytes | Closed in sweep. Child stderr is escaped by byte length, not C-string length. |
| A4 | SIGKILL cannot be recorded | Disclosed. SIGKILL is not catchable; best-effort signal records apply only to tested catchable signals. |
| B5 | Signal handler used non-async-signal-safe `snprintf` | Closed in sweep. Handler now writes fixed static JSON strings with `write(2)` and exits with `_exit`. |
| B6 | `\uXXXX` JSON escapes collapsed to `?` | Closed in sweep for single-code-unit escapes. Parser decodes `\uXXXX` to UTF-8 and rejects surrogate code units. |

## What Changed

Modified:

- `guard/usernotify_exec_guard.c`

Added:

- `scripts/replay_sprint4_audit_integrity.sh`

Key implementation changes:

- Dedicated supervisor audit stream:
  - parent duplicates stderr with `F_DUPFD_CLOEXEC`
  - child stderr is replaced with a pipe
  - child stderr chunks are emitted as escaped `child_stderr` JSON records
- Signal handler:
  - `SIGTERM`, `SIGINT`, and `SIGHUP` emit `supervisor_exit` with `reason=killed_by_signal`
- Policy parser:
  - strict in-process JSON parser for this policy schema
  - `allowed_executables` must be an array
  - entries must be absolute strings
  - escaped strings are handled instead of `strstr`/`strchr` field walking
- Child-context path resolution:
  - `/proc/self/...` resolves through `/proc/<child_pid>/...`
  - absolute paths resolve through `/proc/<child_pid>/root/...`
- Inline SHA256:
  - uses Linux AF_ALG `hash/sha256`
  - no fork/exec of `/usr/bin/sha256sum`
- argv fidelity:
  - emits `argv_truncated`
  - emits `argv_total_count`
  - emits `argv_total_count_capped`
- Sweep hardening:
  - signal handler uses fixed strings and `write(2)`
  - child stderr preserves embedded NULs as JSON escapes
  - JSON parser rejects excessive nesting
  - JSON parser decodes `\uXXXX` escapes instead of replacing them with `?`

## Replay Results

Sprint 4 audit-integrity replay:

- `proofs/sprint4_runs/sprint4-20260430T234709Z`

Result:

```text
PASS compile gcc clean
PASS f1_forged_stderr_is_child_stderr exit=0
PASS f1_forged_stderr_demoted forged JSON escaped as child_stderr
PASS f1_noise_cannot_prefix_supervisor_json exit=0
PASS f1_noise_prefix_closed no child prefix on supervisor JSON
PASS a3_child_stderr_nul_preserved exit=0
PASS a3_child_stderr_nul_preserved embedded NUL preserved in escaped child_stderr
PASS f2_signal_exit_record exit=143
PASS f2_signal_exit_record_present killed_by_signal recorded
PASS f3_policy_string_rejected exit=2
PASS f3_policy_string_rejected_reason malformed policy failed closed
PASS a1_deep_json_rejected exit=2
PASS a1_deep_json_depth_limit deep nested JSON rejected
PASS b6_unicode_policy_id_decoded exit=0
PASS b6_unicode_policy_id_decoded unicode escape decoded
PASS f5_proc_self_exe_child_context exit=0
PASS f5_proc_self_exe_resolved_to_child numeric proc resolution used
PASS f6_no_sha256sum_exec source no longer references sha256sum
PASS f7_argv_truncation_marked exit=0
PASS f7_argv_truncation_fields argv truncation metadata emitted
PASS a2_argv_count_cap_marked exit=0
PASS a2_argv_count_cap_marked argv count cap disclosed
pass=22 fail=0
```

Sprint 2 identity replay after Sprint 4 changes:

- `proofs/sprint2_runs/sprint2-20260430T234710Z`

Result:

```text
pass=12 fail=0
```

Static analyzer compile:

```text
gcc -Wall -Wextra -fanalyzer -O2
exit=0
```

## Hashes

```text
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
0eb54d912bd45024c5fd6d873a628d04bebadb639333a02d012ee9336d10e73e  scripts/replay_sprint4_audit_integrity.sh
a7ae211593b2241614bf0536130042ebe83eb70fba932bc364559386bb51b9d6  scripts/replay_sprint2_identity.sh
```

## Claim Now Allowed

A local seccomp user-notify execution guard can preserve Sprint 2 identity decisions, preserve Sprint 3 Landlock execute-underlay behavior, and emit audit records on a supervisor-owned stream that the supervised child cannot forge by writing JSON to stderr. It records best-effort supervisor termination audit records for tested catchable signal paths, rejects reproduced malformed-policy and excessive-nesting policy cases, resolves `/proc/self/exe` from the child process context for the reproduced nested case, computes SHA256 in-process, preserves embedded NULs in captured child stderr, decodes simple `\uXXXX` policy-string escapes, and marks argv truncation including count saturation.

## Claims Still Not Allowed

- Docker/OpenHands integration is still not proven.
- This is not production sandbox security.
- The `F_CONT` path TOCTOU is still not fully eliminated.
- Signal handling records supervisor death; it does not prevent denial-of-service.
- SIGKILL cannot be caught or recorded by a signal handler.
- The policy parser is strict for the current policy schema; it is not a general-purpose JSON library.
- JSON `\uXXXX` handling covers single code units and rejects surrogate code units; it does not compose surrogate pairs.
- Linux AF_ALG SHA256 is Linux-specific.
- Landlock loader paths remain host-specific and x86-64-oriented.
- The guard remains execute-focused; it does not restrict reads, writes, network, shell builtins, or already-open file descriptors.

## Reviewer Read

Sprint 4 fixes the credibility problem raised by the audits. Sprint 3 made the execution boundary more interesting; Sprint 4 makes the audit trail much harder to dismiss.

The remaining blocker before Docker/OpenHands is no longer "your audit stream is forgeable." The remaining blocker is integration proof: can this exact guard shape run under the target agent runtime without breaking normal workflows?
