#!/bin/sh
set -eu
cp /bin/rm /lab/proofs/sprint5_runs/renamed_rm_python3
chmod 755 /lab/proofs/sprint5_runs/renamed_rm_python3
/lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json /lab/proofs/sprint5_runs/renamed_rm_python3 --version
