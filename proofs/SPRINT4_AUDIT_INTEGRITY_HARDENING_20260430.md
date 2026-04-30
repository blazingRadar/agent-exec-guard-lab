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

## Replay Results

Sprint 4 audit-integrity replay:

- `proofs/sprint4_runs/sprint4-20260430T232441Z`

Result:

```text
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
```

Sprint 2 identity replay after Sprint 4 changes:

- `proofs/sprint2_runs/sprint2-20260430T232453Z`

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
4d59cb357cea8577057ebb861294f1623768e5d973e0bfd3be80e573792e3d07  guard/usernotify_exec_guard.c
0bb35fd4ab75dc28aa9e1e9334dbee3646b25bb1902117abfe94f12ad536b61c  bin/usernotify_exec_guard
afddc594ae1716aaed54725d4a346cdcfa351a54b881fb8a0b89719c86839d4a  scripts/replay_sprint4_audit_integrity.sh
a7ae211593b2241614bf0536130042ebe83eb70fba932bc364559386bb51b9d6  scripts/replay_sprint2_identity.sh
```

## Claim Now Allowed

A local seccomp user-notify execution guard can preserve Sprint 2 identity decisions, preserve Sprint 3 Landlock execute-underlay behavior, and emit audit records on a supervisor-owned stream that the supervised child cannot forge by writing JSON to stderr. It records signal-kill termination, rejects the reproduced malformed-policy fail-open case, resolves `/proc/self/exe` from the child process context for the reproduced nested case, computes SHA256 in-process, and marks argv truncation.

## Claims Still Not Allowed

- Docker/OpenHands integration is still not proven.
- This is not production sandbox security.
- The `F_CONT` path TOCTOU is still not fully eliminated.
- Signal handling records supervisor death; it does not prevent denial-of-service.
- The policy parser is strict for the current policy schema; it is not a general-purpose JSON library.
- Linux AF_ALG SHA256 is Linux-specific.
- Landlock loader paths remain host-specific and x86-64-oriented.
- The guard remains execute-focused; it does not restrict reads, writes, network, shell builtins, or already-open file descriptors.

## CTO Read

Sprint 4 fixes the credibility problem raised by the audits. Sprint 3 made the execution boundary more interesting; Sprint 4 makes the audit trail much harder to dismiss.

The remaining blocker before Docker/OpenHands is no longer "your audit stream is forgeable." The remaining blocker is integration proof: can this exact guard shape run under the target agent runtime without breaking normal workflows?
