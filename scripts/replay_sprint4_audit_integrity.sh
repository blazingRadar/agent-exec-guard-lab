#!/usr/bin/env bash
set -u

ROOT="/home/blazingradar/agent-exec-guard-lab"
GUARD="$ROOT/bin/usernotify_exec_guard"
SRC="$ROOT/src/usernotify_exec_guard.c"
POLICY="$ROOT/policy/sprint2.allow.json"
RUN_ID="sprint4-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="$ROOT/proofs/sprint4_runs/$RUN_ID"
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

count = 0
for line in open(sys.argv[1], "r", encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith("{"):
        continue
    json.loads(line)
    count += 1
if count == 0:
    raise SystemExit("no json audit lines found")
PY
}

json_query() {
  local stderr_file="$1"
  local expr="$2"
  python3 - "$stderr_file" "$expr" <<'PY'
import json
import sys

path, expr = sys.argv[1:3]
for line in open(path, "r", encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith("{"):
        continue
    obj = json.loads(line)
    if eval(expr, {}, {"obj": obj}):
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
  record "PASS" "$name" "exit=$rc"
}

printf 'run_id=%s\n' "$RUN_ID" >"$RUN_ROOT/replay_summary.txt"
printf 'root=%s\n' "$ROOT" >>"$RUN_ROOT/replay_summary.txt"

if ! compile_guard; then
  record "FAIL" "compile" "gcc failed"
  printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
  exit 1
fi
record "PASS" "compile" "gcc clean"

run_case "f1_forged_stderr_is_child_stderr" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import sys; sys.stderr.write("{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED\"}\n"); sys.stderr.flush()'
if json_valid "$RUN_ROOT/f1_forged_stderr_is_child_stderr/stderr.txt" >"$RUN_ROOT/f1_forged_stderr_is_child_stderr/json_check.stdout" 2>"$RUN_ROOT/f1_forged_stderr_is_child_stderr/json_check.stderr" &&
   json_query "$RUN_ROOT/f1_forged_stderr_is_child_stderr/stderr.txt" 'obj.get("event") == "child_stderr" and "FORGED" in obj.get("data", "")' &&
   ! json_query "$RUN_ROOT/f1_forged_stderr_is_child_stderr/stderr.txt" 'obj.get("event") == "exec_decision" and obj.get("reason") == "FORGED"'; then
  record "PASS" "f1_forged_stderr_demoted" "forged JSON escaped as child_stderr"
else
  record "FAIL" "f1_forged_stderr_demoted" "forged JSON reached audit stream as decision"
fi

run_case "f1_noise_cannot_prefix_supervisor_json" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import sys; sys.stderr.write("NOISE-"); sys.stderr.flush()'
if json_valid "$RUN_ROOT/f1_noise_cannot_prefix_supervisor_json/stderr.txt" >"$RUN_ROOT/f1_noise_cannot_prefix_supervisor_json/json_check.stdout" 2>"$RUN_ROOT/f1_noise_cannot_prefix_supervisor_json/json_check.stderr" &&
   ! grep -q '^NOISE-{' "$RUN_ROOT/f1_noise_cannot_prefix_supervisor_json/stderr.txt"; then
  record "PASS" "f1_noise_prefix_closed" "no child prefix on supervisor JSON"
else
  record "FAIL" "f1_noise_prefix_closed" "child prefix corrupted JSON line"
fi

run_case "a3_child_stderr_nul_preserved" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import sys; sys.stderr.buffer.write(b"A\x00B"); sys.stderr.flush()'
if json_query "$RUN_ROOT/a3_child_stderr_nul_preserved/stderr.txt" 'obj.get("event") == "child_stderr" and obj.get("data") == "A\x00B"'; then
  record "PASS" "a3_child_stderr_nul_preserved" "embedded NUL preserved in escaped child_stderr"
else
  record "FAIL" "a3_child_stderr_nul_preserved" "embedded NUL not preserved"
fi

run_case "f2_signal_exit_record" 143 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import os, signal; os.kill(os.getppid(), signal.SIGTERM)'
if json_query "$RUN_ROOT/f2_signal_exit_record/stderr.txt" 'obj.get("event") == "supervisor_exit" and obj.get("reason") == "killed_by_signal"'; then
  record "PASS" "f2_signal_exit_record_present" "killed_by_signal recorded"
else
  record "FAIL" "f2_signal_exit_record_present" "missing killed_by_signal record"
fi

cat > "$WORK/spoof_policy.json" <<'JSON'
{"policy_id":"spoof","allowed_executables":"should_be_array","extra":["/bin/echo"],"more_paths":["/bin/rm"]}
JSON
run_case "f3_policy_string_rejected" 2 timeout 5 "$GUARD" --policy "$WORK/spoof_policy.json" /bin/echo SPOOF_TEST
if ! grep -q 'SPOOF_TEST' "$RUN_ROOT/f3_policy_string_rejected/stdout.txt" &&
   grep -q 'allowed_executables must be array' "$RUN_ROOT/f3_policy_string_rejected/stderr.txt"; then
  record "PASS" "f3_policy_string_rejected_reason" "malformed policy failed closed"
else
  record "FAIL" "f3_policy_string_rejected_reason" "malformed policy not rejected cleanly"
fi

cat > "$WORK/deep_policy.json" <<'JSON'
{"policy_id":"deep","allowed_executables":["/bin/echo"],"extra":
JSON
python3 - "$WORK/deep_policy.json" <<'PY'
import sys
path = sys.argv[1]
with open(path, "a", encoding="utf-8") as f:
    f.write("[" * 80)
    f.write("0")
    f.write("]" * 80)
    f.write("}\n")
PY
run_case "a1_deep_json_rejected" 2 timeout 5 "$GUARD" --policy "$WORK/deep_policy.json" /bin/echo DEEP_TEST
if ! grep -q 'DEEP_TEST' "$RUN_ROOT/a1_deep_json_rejected/stdout.txt" &&
   grep -q 'malformed JSON value' "$RUN_ROOT/a1_deep_json_rejected/stderr.txt"; then
  record "PASS" "a1_deep_json_depth_limit" "deep nested JSON rejected"
else
  record "FAIL" "a1_deep_json_depth_limit" "deep nested JSON was not rejected cleanly"
fi

cat > "$WORK/unicode_policy.json" <<'JSON'
{"policy_id":"unicode-\u0041","allowed_executables":["/bin/echo"]}
JSON
run_case "b6_unicode_policy_id_decoded" 0 timeout 5 "$GUARD" --policy "$WORK/unicode_policy.json" /bin/echo UNICODE_TEST
if json_query "$RUN_ROOT/b6_unicode_policy_id_decoded/stderr.txt" 'obj.get("policy_id") == "unicode-A"'; then
  record "PASS" "b6_unicode_policy_id_decoded" "unicode escape decoded"
else
  record "FAIL" "b6_unicode_policy_id_decoded" "unicode escape not decoded"
fi

run_case "f5_proc_self_exe_child_context" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import os; os.execv("/proc/self/exe", ["/proc/self/exe", "--version"])'
PY_REALPATH="$(realpath /usr/bin/python3)"
if json_query "$RUN_ROOT/f5_proc_self_exe_child_context/stderr.txt" 'obj.get("event") == "exec_decision" and obj.get("raw_exe") == "/proc/self/exe" and obj.get("realpath") == "'"$PY_REALPATH"'"'; then
  record "PASS" "f5_proc_self_exe_resolved_to_child" "numeric proc resolution used"
else
  record "FAIL" "f5_proc_self_exe_resolved_to_child" "proc self exe did not resolve to child executable"
fi

if ! grep -q 'sha256sum' "$SRC"; then
  record "PASS" "f6_no_sha256sum_exec" "source no longer references sha256sum"
else
  record "FAIL" "f6_no_sha256sum_exec" "source still references sha256sum"
fi

run_case "f7_argv_truncation_marked" 0 timeout 5 "$GUARD" --policy "$POLICY" /bin/echo a b c d e f g h i j k l
if json_query "$RUN_ROOT/f7_argv_truncation_marked/stderr.txt" 'obj.get("event") == "exec_decision" and obj.get("argv_truncated") is True and int(obj.get("argv_total_count", 0)) > 8 and obj.get("argv_total_count_capped") is False'; then
  record "PASS" "f7_argv_truncation_fields" "argv truncation metadata emitted"
else
  record "FAIL" "f7_argv_truncation_fields" "missing argv truncation metadata"
fi

run_case "a2_argv_count_cap_marked" 0 timeout 5 "$GUARD" --policy "$POLICY" /usr/bin/python3 -c 'import os; os.execv("/bin/echo", ["echo"] + [str(i) for i in range(300)])'
if json_query "$RUN_ROOT/a2_argv_count_cap_marked/stderr.txt" 'obj.get("event") == "exec_decision" and obj.get("raw_exe") == "/bin/echo" and obj.get("argv_truncated") is True and obj.get("argv_total_count") == 256 and obj.get("argv_total_count_capped") is True'; then
  record "PASS" "a2_argv_count_cap_marked" "argv count cap disclosed"
else
  record "FAIL" "a2_argv_count_cap_marked" "argv count cap not disclosed"
fi

sha256sum "$SRC" "$GUARD" >"$RUN_ROOT/sha256s.txt"

printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$RUN_ROOT/replay_summary.txt"
printf 'run_root=%s\n' "$RUN_ROOT" | tee -a "$RUN_ROOT/replay_summary.txt"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0
