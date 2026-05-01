#!/bin/sh
set -eu
cp /bin/rm "$(dirname "$0")/renamed_rm_python3"
chmod 755 "$(dirname "$0")/renamed_rm_python3"
/lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json "$(dirname "$0")/renamed_rm_python3" --version
