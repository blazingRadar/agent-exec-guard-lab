# Sprint 3 Command Log

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`

## Commands

```bash
mkdir -p /home/blazingradar/agent-exec-guard-lab/proofs/sprint3_scratch
```

Created lab-local scratch area. No retained `/tmp` artifacts are part of this sprint.

```bash
gcc -Wall -Wextra -O2 -o landlock_file_exec_probe landlock_file_exec_probe.c
gcc -Wall -Wextra -O2 -static -o allowed_static static_probe_payload.c
cp allowed_static blocked_static
./landlock_file_exec_probe ./allowed_static ./blocked_static
```

Result: `RESULT file_level_execute_rule=PASS`.

```bash
gcc -Wall -Wextra -O2 -o landlock_dynamic_exec_probe landlock_dynamic_exec_probe.c
readelf -l /usr/bin/git | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
realpath /usr/bin/git /lib64/ld-linux-x86-64.so.2
cp /usr/bin/git ./git_blocked_copy
chmod 755 ./git_blocked_copy
./landlock_dynamic_exec_probe /usr/bin/git ./git_blocked_copy /usr/bin/git /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
```

Result: `RESULT dynamic_exact_execute_rules=PASS`.

```bash
gcc -Wall -Wextra -O2 -o landlock_replace_path_probe landlock_replace_path_probe.c
cp allowed_static replace_allowed
cp blocked_static replace_blocked
./landlock_replace_path_probe ./replace_allowed ./replace_blocked
```

Result: `RESULT replacement_path_exec_denied=PASS`.

```bash
gcc -Wall -Wextra -O2 -static -o replacement_static static_replacement_payload.c
cp allowed_static replace_allowed_distinct
cp replacement_static replace_blocked_distinct
./landlock_replace_path_probe ./replace_allowed_distinct ./replace_blocked_distinct
```

Result: `RESULT replacement_path_exec_denied=PASS`.

```bash
./scripts/replay_sprint2_identity.sh
```

Result:

```text
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T230741Z
```

```bash
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard proofs/sprint3_scratch/*.c proofs/sprint3_scratch/landlock_*_probe
```

Hashes recorded in `SPRINT3_LANDLOCK_UNDERLAY_20260430.md`.

```bash
gcc -Wall -Wextra -fanalyzer -O2 -o /tmp/usernotify_exec_guard_analyzer guard/usernotify_exec_guard.c
rm -f /tmp/usernotify_exec_guard_analyzer
```

Result: analyzer compile exited 0 with no emitted diagnostics. The temporary analyzer binary was removed.
