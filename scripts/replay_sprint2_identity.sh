#!/usr/bin/env bash
set -u

ROOT="/home/blazingradar/agent-exec-guard-lab"
GUARD="$ROOT/bin/usernotify_exec_guard"
SRC="$ROOT/guard/usernotify_exec_guard.c"
POLICY="$ROOT/policy/sprint2.allow.json"
ORIGINAL_PATH="$PATH"
RUN_ID="sprint2-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint2_runs/$RUN_ID"
WORK="$RUN_ROOT/work"

mkdir -p "$WORK"

pass_count=0
fail_count=0

record() {
  local status="$1"
  local name="$2"
  local message="$3"
  printf '%s %s %s\n' "$status" "$name" "$message" | tee -a "$RUN_ROOT/replay_summary.txt"
  if [ "$status" = "PASS" ]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
}

compile_guard() {
  gcc -Wall -Wextra -O2 -o "$GUARD" "$SRC" >"$RUN_ROOT/compile.stdout" 2>"$RUN_ROOT/compile.stderr"
}

json_valid() {
  local stderr_file="$1"
  python3 - "$stderr_file" <<'PY'
import json
import sys

path = sys.argv[1]
count = 0
with open(path, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line.startswith("{"):
            continue
        json.loads(line)
        count += 1
if count == 0:
    raise SystemExit("no json audit lines found")
PY
}

json_has() {
  local stderr_file="$1"
  local key="$2"
  local value="$3"
  python3 - "$stderr_file" "$key" "$value" <<'PY'
import json
import sys

path, key, value = sys.argv[1:4]
for line in open(path, "r", encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith("{"):
        continue
    obj = json.loads(line)
    if str(obj.get(key)) == value:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

run_case() {
  local name="$1"
  local expected_exit="$2"
  shift 2
  local case_dir="$RUN_ROOT/$name"
  mkdir -p "$case_dir"

  "$@" >"$case_dir/stdout.txt" 2>"$case_dir/stderr.txt"
  local rc=$?
  printf '%s\n' "$rc" >"$case_dir/exit_code.txt"
  printf '%q ' "$@" >"$case_dir/command.txt"
  printf '\n' >>"$case_dir/command.txt"

  if [ "$rc" -ne "$expected_exit" ]; then
    record "FAIL" "$name" "expected_exit=$expected_exit actual_exit=$rc"
    return
  fi
  if ! json_valid "$case_dir/stderr.txt" >"$case_dir/json_check.stdout" 2>"$case_dir/json_check.stderr"; then
    record "FAIL" "$name" "json audit invalid"
    return
  fi
  record "PASS" "$name" "exit=$rc json=valid"
}

printf 'run_id=%s\n' "$RUN_ID" >"$RUN_ROOT/replay_summary.txt"
printf 'root=%s\n' "$ROOT" >>"$RUN_ROOT/replay_summary.txt"

if ! compile_guard; then
  record "FAIL" "compile" "gcc failed"
  printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
  exit 1
fi
record "PASS" "compile" "gcc clean"

run_case "allow_git" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/git --version
json_has "$RUN_ROOT/allow_git/stderr.txt" decision ALLOW || record "FAIL" "allow_git_decision" "missing ALLOW"

run_case "direct_block_rm" 126 timeout 5 "$GUARD" --policy "$POLICY" /bin/rm --version
json_has "$RUN_ROOT/direct_block_rm/stderr.txt" decision BLOCK || record "FAIL" "direct_block_rm_decision" "missing BLOCK"
if grep -q 'rm (GNU coreutils)' "$RUN_ROOT/direct_block_rm/stdout.txt"; then
  record "FAIL" "direct_block_rm_output" "rm output appeared"
else
  record "PASS" "direct_block_rm_output" "rm output absent"
fi

run_case "bash_nested_block_rm" 126 timeout 5 "$GUARD" --policy "$POLICY" /bin/bash --noprofile --norc -lc '/bin/rm --version'
json_has "$RUN_ROOT/bash_nested_block_rm/stderr.txt" decision BLOCK || record "FAIL" "bash_nested_decision" "missing BLOCK"

run_case "python_nested_block_rm" 1 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import subprocess; subprocess.run(["/bin/rm", "--version"], check=True)'
json_has "$RUN_ROOT/python_nested_block_rm/stderr.txt" decision BLOCK || record "FAIL" "python_nested_decision" "missing BLOCK"

cp /bin/rm "$WORK/git"
chmod 755 "$WORK/git"
run_case "copy_rename_bypass_blocked" 126 timeout 5 "$GUARD" --policy "$POLICY" "$WORK/git" --version
json_has "$RUN_ROOT/copy_rename_bypass_blocked/stderr.txt" reason blocked_executable_identity || record "FAIL" "copy_bypass_reason" "missing identity block"
if grep -q 'rm (GNU coreutils)' "$RUN_ROOT/copy_rename_bypass_blocked/stdout.txt"; then
  record "FAIL" "copy_bypass_output" "renamed rm executed"
else
  record "PASS" "copy_bypass_output" "renamed rm did not execute"
fi

ln -sf /bin/rm "$WORK/python3"
run_case "symlink_bypass_blocked" 126 timeout 5 "$GUARD" --policy "$POLICY" "$WORK/python3" --version
json_has "$RUN_ROOT/symlink_bypass_blocked/stderr.txt" reason blocked_executable_identity || record "FAIL" "symlink_reason" "missing identity block"

run_case "env_path_bypass_blocked" 126 env PATH="$WORK:$ORIGINAL_PATH" timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/env python3 --version
json_has "$RUN_ROOT/env_path_bypass_blocked/stderr.txt" reason blocked_executable_identity || record "FAIL" "env_path_reason" "missing identity block"

printf '#!/bin/sh\necho SHOULD_NOT_RUN\n' > "$WORK/bad\"name"
chmod 755 "$WORK/bad\"name"
run_case "json_escape_hostile_path" 126 timeout 5 "$GUARD" --policy "$POLICY" "$WORK/bad\"name"
json_has "$RUN_ROOT/json_escape_hostile_path/stderr.txt" decision BLOCK || record "FAIL" "json_escape_decision" "missing BLOCK"

run_case "execveat_blocked" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import ctypes; libc=ctypes.CDLL(None, use_errno=True); argv=(ctypes.c_char_p*3)(b"rm", b"--version", None); env=(ctypes.c_char_p*1)(None); rc=libc.syscall(322, -100, b"/bin/rm", argv, env, 0); e=ctypes.get_errno(); print("execveat_rc", rc, "errno", e); raise SystemExit(0 if rc == -1 and e == 1 else 3)'
json_has "$RUN_ROOT/execveat_blocked/stderr.txt" reason execveat_not_supported_in_sprint2 || record "FAIL" "execveat_reason" "missing execveat block"

sha256sum "$SRC" "$GUARD" >"$RUN_ROOT/sha256s.txt"

printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
printf 'run_root=%s\n' "$RUN_ROOT" | tee -a "$RUN_ROOT/replay_summary.txt"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
