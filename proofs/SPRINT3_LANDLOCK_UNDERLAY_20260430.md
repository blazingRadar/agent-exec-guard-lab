# Sprint 3 Landlock Underlay Proof

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: bounded implementation sprint. No Docker, no OpenHands, no private governance-layer import.

## Decision

Sprint 3 is worth doing.

The decisive finding is that Landlock can grant `LANDLOCK_ACCESS_FS_EXECUTE` to specific executable files on this host, not only broad parent directories. That means the underlay can be tight enough to materially reduce the `SECCOMP_USER_NOTIF_FLAG_CONTINUE` caveat without turning the guard into a different architecture.

## What Changed

Modified:

- `guard/usernotify_exec_guard.c`

Added:

- `proofs/sprint3_scratch/landlock_file_exec_probe.c`
- `proofs/sprint3_scratch/landlock_dynamic_exec_probe.c`
- `proofs/sprint3_scratch/landlock_replace_path_probe.c`
- `proofs/sprint3_scratch/static_probe_payload.c`
- `proofs/sprint3_scratch/static_replacement_payload.c`

The guard now installs a child-side Landlock execute underlay after the seccomp listener is installed and sent to the supervisor, but before the supervised command is executed.

Landlock rules added:

- exact file execute rules for every resolved executable in `policy/sprint2.allow.json`
- exact file execute rules for common dynamic loader paths:
  - `/lib64/ld-linux-x86-64.so.2`
  - `/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`
  - `/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`

The ruleset handles only `LANDLOCK_ACCESS_FS_EXECUTE`. It does not attempt to restrict read/write/open behavior.

## Probe Results

### Probe 1: file-level execute rules

Artifact:

- `proofs/sprint3_scratch/landlock_file_exec_probe.c`

Result:

```text
landlock_abi=7
execute_flag=0x1
allowed_exec_exit=0
blocked_exec_exit=126
RESULT file_level_execute_rule=PASS
```

Meaning:

Landlock allowed execution of the exact file object granted by rule and denied an adjacent executable file with `EACCES`.

### Probe 2: dynamic executable exact rules

Artifact:

- `proofs/sprint3_scratch/landlock_dynamic_exec_probe.c`

Result:

```text
git version 2.43.0
landlock_abi=7
target_exec_exit=0
blocked_exec_exit=126
RESULT dynamic_exact_execute_rules=PASS
```

Meaning:

Exact execute rules for `/usr/bin/git` plus the dynamic loader allowed real `git --version`, while an identical copied `git` binary outside the policy set was denied with `EACCES`.

### Probe 3: path replacement after rule installation

Artifact:

- `proofs/sprint3_scratch/landlock_replace_path_probe.c`

Result:

```text
landlock_abi=7
exec_after_replace_errno=13 Permission denied
RESULT replacement_path_exec_denied=PASS
```

Meaning:

After Landlock granted execute to an original file, replacing that pathname with a different executable did not inherit execute permission. The replacement was denied at exec time.

This directly addresses the filesystem-swap half of the Sprint 2 caveat.

## Replay Result

Existing Sprint 2 replay was rerun after adding the Landlock underlay.

Run root:

- `proofs/sprint2_runs/sprint2-20260430T230741Z`

Result:

```text
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
```

Meaning:

Sprint 3 preserved the Sprint 2 behavior while adding the Landlock execute underlay.

## Hashes

```text
ff540da83e4b7f2a55d3535f08d038dc78e7be7c0cdb2a1844beb761d4461bd3  guard/usernotify_exec_guard.c
ab53dfb1e5235fcff5d782b21bb5910a6c2c0cb997d102731428173536369b94  bin/usernotify_exec_guard
3202e551411ee1d04ab8302aedb58e715e62102080773977d6cfb556ad5a93f6  proofs/sprint3_scratch/landlock_dynamic_exec_probe.c
cdb85eb28649cd509e846508fdb3020dcc5c9cbf98b70e8663b3da83d9c5cfba  proofs/sprint3_scratch/landlock_file_exec_probe.c
2aef6c5d44fb5cc63b971da8d3ea6d5bbb51d69d783385ccbbc69c6e18817221  proofs/sprint3_scratch/landlock_replace_path_probe.c
```

## Claim Now Allowed

A local seccomp user-notify execution guard can preserve Sprint 2 file-backed executable identity checks while adding a child-inherited Landlock execute underlay. On this host, the underlay grants execute to exact policy executable files plus the dynamic loader, denies copied non-policy executables, and denies a replaced executable at a previously allowed pathname. The existing 12-case Sprint 2 replay still passes.

## Claims Still Not Allowed

- This does not prove Docker integration.
- This does not prove OpenHands integration.
- This does not prove production sandbox security.
- This does not eliminate every theoretical `F_CONT` concern.
- This does not make the audit row cryptographically prove the exact object executed after `F_CONT`.
- This does not support `execveat`; the guard still conservatively blocks tested `execveat`.
- This does not restrict reads, writes, network, file creation, or shell builtins. It is an execute underlay only.

## CTO Read

This is worth doing and worth keeping.

The earlier caveat was real. Sprint 2 validated identity at notification time and then resumed a path-based syscall. Sprint 3 does not magically turn `F_CONT` into fd-stable execution, but it does add a second kernel-enforced layer at actual exec time. The important practical result is that post-decision swaps to non-policy executables are denied by Landlock even if the original path machinery is raced.

The honest demo framing should be:

> Seccomp decides; Landlock enforces the executable universe underneath it.

Do not frame this as a complete sandbox. Frame it as a narrow hard execution gate for agent subprocesses, with preserved JSON audit and fail-closed behavior.
