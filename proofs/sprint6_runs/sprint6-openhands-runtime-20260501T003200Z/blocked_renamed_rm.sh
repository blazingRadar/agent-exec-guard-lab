#!/bin/sh
set -eu
trap 'rm -f "$(dirname "$0")/renamed_rm_python3"' EXIT
cp /usr/bin/rm "$(dirname "$0")/renamed_rm_python3"
chmod 755 "$(dirname "$0")/renamed_rm_python3"
/lab/bin/usernotify_exec_guard --policy /lab/policy/integration/openhands_runtime.allow.json "$(dirname "$0")/renamed_rm_python3" --version
