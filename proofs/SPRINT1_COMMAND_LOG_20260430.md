# Sprint 1 Command Log

Date: 2026-04-30

This file records commands and observed results for the raw runtime boundary sprint.

## Commands

### Environment

```bash
docker version
```

Observed:

```text
Client: Docker Engine - Community
 Version:           29.1.3
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

```bash
id
```

Observed:

```text
uid=1001(blazingradar) gid=1001(blazingradar) groups=1001(blazingradar),27(sudo),100(users)
```

```bash
ls -l /var/run/docker.sock
```

Observed:

```text
srw-rw---- 1 root docker 0 Feb 24 21:14 /var/run/docker.sock
```

```bash
pkg-config --libs --cflags libseccomp
```

Observed:

```text
Package 'libseccomp', required by 'virtual:world', not found
```

### Compile

```bash
gcc -Wall -Wextra -O2 -o /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard /home/blazingradar/agent-exec-guard-lab/guard/usernotify_exec_guard.c
```

Observed: compile succeeded with no output.

### Baseline

```bash
/bin/rm --version | head -1; printf 'exit=%s\n' "$?"
```

Observed:

```text
rm (GNU coreutils) 9.4
exit=0
```

### Guarded Direct Block

```bash
timeout 5 /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard /bin/rm --version; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
execvp: Operation not permitted
exit=126
```

### Guarded Allow

```bash
timeout 5 /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard /usr/bin/git --version; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/usr/bin/git","policy":"sprint1_hardcoded_allowlist"}
git version 2.43.0
exit=0
```

### Guarded Nested Block

```bash
timeout 5 /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard /usr/bin/python3 -c 'import subprocess; subprocess.run(["/bin/rm", "--version"], check=True)'; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/usr/bin/python3","policy":"sprint1_hardcoded_allowlist"}
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
PermissionError: [Errno 1] Operation not permitted: '/bin/rm'
exit=1
```

### Guarded Shell Block

```bash
timeout 5 /home/blazingradar/agent-exec-guard-lab/bin/usernotify_exec_guard /bin/bash --noprofile --norc -lc '/bin/rm --version'; printf 'exit=%s\n' "$?"
```

Observed:

```text
{"decision":"ALLOW","reason":"allowed_executable","exe":"/bin/bash","policy":"sprint1_hardcoded_allowlist"}
{"decision":"BLOCK","reason":"blocked_executable","exe":"/bin/rm","policy":"sprint1_hardcoded_allowlist"}
/bin/bash: line 1: /bin/rm: Operation not permitted
exit=126
```
