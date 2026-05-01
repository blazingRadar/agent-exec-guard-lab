#!/bin/sh
set -eu
printf 'cmdline='
tr '\000' ' ' </proc/1/cmdline
printf '\n'
printf 'PATH=%s\n' "$PATH"
printf 'pwd=%s\n' "$(pwd)"
printf 'commands:\n'
for c in python3 bash sh cat rm git node npm poetry micromamba code; do command -v "$c" 2>/dev/null || true; done
printf 'openhands paths:\n'
find /openhands -maxdepth 4 -type f 2>/dev/null | sed -n '1,240p'
