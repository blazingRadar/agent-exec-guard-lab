# Sprint 2 Command Log

Date: 2026-04-30

Commands and observations from the identity hardening sprint.

## Compile

```bash
gcc -Wall -Wextra -O2 -o /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard /home/blazingradar/agent-exec-guard-lab/guard/usernotify_exec_guard.c
```

Observed:

```text
compile succeeded cleanly
```

## First Replay Attempt

```bash
/home/blazingradar/agent-exec-guard-lab/scripts/replay_sprint2_identity.sh
```

Run root:

```text
/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T220518Z
```

Observed:

```text
pass=10 fail=2
```

Failure:

- `env_path_bypass_blocked` produced a valid guard outcome, but the replay harness polluted its own `PATH`.
- The harness then invoked the fake `python3` symlink while trying to validate JSON.
- This was a replay-script bug, not a guard failure.
- The failed run is preserved.

Fix:

- changed the env-path case to invoke `env PATH=... timeout ...` inside `run_case`
- restored validation tools to the original harness `PATH`

## Passing Replay 1

```bash
/home/blazingradar/agent-exec-guard-lab/scripts/replay_sprint2_identity.sh
```

Run root:

```text
/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T220552Z
```

Observed:

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
pass=11 fail=0
```

## Passing Replay 2

```bash
/home/blazingradar/agent-exec-guard-lab/scripts/replay_sprint2_identity.sh
```

Run root:

```text
/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T220610Z
```

Observed:

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
pass=11 fail=0
```

## Passing Replay 3: Execveat Probe Added

```bash
/home/blazingradar/agent-exec-guard-lab/scripts/replay_sprint2_identity.sh
```

Run root:

```text
/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T220722Z
```

Observed:

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

## Final Hashes

From passing replay 1:
Also current after replay 3:

```text
58b8409de0c53d4be2e742cac11877902b1c6249c9e8a4a06e7b053314a4aae2  /home/blazingradar/agent-exec-guard-lab/guard/usernotify_exec_guard.c
40e156ab3d7df5cd17b3521ee7608a8e756698ba203dc124e47e4e8b1a177415  /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard
```
