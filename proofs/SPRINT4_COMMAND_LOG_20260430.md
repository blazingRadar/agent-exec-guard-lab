# Sprint 4 Command Log

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`

## Commands

```bash
pkg-config --exists jansson && pkg-config --cflags --libs jansson || true
pkg-config --exists json-c && pkg-config --cflags --libs json-c || true
```

Result: no local `pkg-config` output for jansson/json-c.

```bash
printf '#include <openssl/sha.h>\nint main(){return 0;}\n' | gcc -x c - -lcrypto -o proofs/sprint3_scratch/openssl_probe
```

Result: OpenSSL headers not installed. No system dependency added.

```bash
gcc -Wall -Wextra -O2 -o bin/usernotify_exec_guard guard/usernotify_exec_guard.c
```

Initial result: one ignored-write warning in the signal handler. Fixed, then recompiled clean.

```bash
./scripts/replay_sprint2_identity.sh
```

Result after Sprint 4 code changes:

```text
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T232321Z
```

```bash
chmod +x scripts/replay_sprint4_audit_integrity.sh
./scripts/replay_sprint4_audit_integrity.sh
```

First result:

```text
pass=13 fail=1
```

The failed case expected `/proc/self/exe` to resolve to `/usr/bin/python3`, but the system realpath is `/usr/bin/python3.12`. The harness was corrected to compare against `realpath /usr/bin/python3`.

```bash
./scripts/replay_sprint4_audit_integrity.sh
```

Final Sprint 4 result:

```text
pass=14 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260430T232441Z
```

```bash
./scripts/replay_sprint2_identity.sh
```

Final Sprint 2 baseline result after Sprint 4:

```text
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T232453Z
```

```bash
gcc -Wall -Wextra -fanalyzer -O2 -o proofs/sprint3_scratch/usernotify_exec_guard_analyzer guard/usernotify_exec_guard.c
rm -f proofs/sprint3_scratch/usernotify_exec_guard_analyzer
```

Result: analyzer compile exited 0 with no emitted diagnostics. Temporary analyzer binary was removed.

```bash
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard scripts/replay_sprint4_audit_integrity.sh scripts/replay_sprint2_identity.sh
```

Hashes recorded in `SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`.
