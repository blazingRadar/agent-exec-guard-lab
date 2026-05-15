# Sprint 10 — Auditor A Independent Review

Date: 2026-05-01
Auditor: A (solo, adversarial; parallel Auditor B running same brief, no coordination).
Posture: independent line-by-line review of Sprint 10's observe/generate/review/enforce policy workflow.
Source of record: live commands on the prepared lab checkout, preserved artifacts, and crafted-input probes against `scripts/policy/generate_policy_from_audit.py`.

---

## 1. Audit Question and Source of Record

Did Sprint 10 deliver a closed observe → generate → review → enforce loop that is honest about (a) what the generator validates and does not validate, (b) the threat model the generated policy inherits from its observation source, and (c) what changed and what did not change versus Sprint 9?

Sources:
- `proofs/SPRINT10_GATE_20260501.md`
- `proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md`
- `proofs/SPRINT10_COMMAND_LOG_20260501.md`
- `scripts/policy/generate_policy_from_audit.py` (read line-by-line)
- `scripts/demo/observe_generate_review_enforce.sh` (read line-by-line)
- `scripts/demo/run_openhands_guard_demo.sh` (carry-forward state)
- `scripts/policy/compile_policy.py`
- `docs/POLICY_WORKFLOW.md`
- `policy/examples/openhands_action_server.yaml` (Sprint 9 hand-rolled)
- `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/` (passing run)
- `proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z/` (preserved failed run)
- `proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined` (input audit log, 130 exec_decision records)
- `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/` (the enforce rerun)
- `proofs/AUDIT_20260501_sprint9_independent_review_orchestrator_pass2.md`
- `proofs/SPRINT9_POST_AUDIT_CLEANUP_20260501.md`

---

## 2. Verdict

**The generated policy reproduces, the closed loop closes, the headline numbers (8 / 14 / 11) replay from preserved artifacts, and the guard SHAs are unchanged. But the generator is more permissive than its written claim suggests: under crafted input, an ALLOW record and a BLOCK record sharing the same `realpath` both pass through, and the proof memo's wording "blocked records are excluded from allowed_executables" is therefore misleading at the threat-model level. The natural-data run is fine because no overlap exists; the generator's invariant is fragile.**

Qualifier: this is a *tooling* sprint, not a *kernel* sprint. The findings here are about the new tooling's input-validation posture and documentation, not about the guard itself. Headline reproducibility holds.

---

## 3. Discipline Check

- **Pre-registration: clean.** Gate `6d91c21` landed at `2026-05-01 00:58:07 -0700`; proof `ef9cb75` landed at `2026-05-01 01:02:52 -0700`. Gate precedes proof by ~4 min 45 s. Pattern matches prior sprints.
- **Carry-Forward Open Items table: present** in the proof memo (Public clone-and-run, recorded outreach video, F4 TOCTOU, non-`CmdRunAction`, full web UI, production-grade sandbox claim). All carried forward correctly.
- **Sprint 9 cleanup learnings carried forward into the Sprint 10 runner:**
  - Self-locating `ROOT="${AEG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"`: **YES** (line 4).
  - Trap-based finish writing `pass=N fail=N`: **YES** (lines 72-77).
  - Aggregate `pass=N fail=N` row in summary: **YES** (`pass=8 fail=0` at end of `workflow_summary.txt`).
  - Preflight checks: **PARTIAL.** Sprint 10 has no preflight stanza of its own (no check that `scripts/policy/generate_policy_from_audit.py`, `scripts/policy/compile_policy.py`, or `scripts/demo/run_openhands_guard_demo.sh` are present/executable; no Docker preflight). Mitigated by the fact that the inner `run_openhands_guard_demo.sh` invocation does its own preflight. But Sprint 10's outer wrapper inherits the *outcome* of Sprint 9's cleanup without inheriting the *pattern* completely.
  - Container cleanup: **N/A** for Sprint 10's outer wrapper (it does not directly start containers). The inner Sprint 9 runner's `cleanup_runtime` trap does the work.
- **One regression vs Sprint 9 cleanup discipline:** the recorded `command_log.txt` and `SPRINT10_COMMAND_LOG_20260501.md` contained a local env-file path in the original proof artifacts. The runner itself accepts a generic `--env-file PATH` and `docs/POLICY_WORKFLOW.md` correctly uses `.env.local`, so this was only a proof-artifact path disclosure. Low severity but a discipline regression worth naming.

---

## 4. Generator Threat-Model Evaluation (load-bearing for Sprint 10)

`scripts/policy/generate_policy_from_audit.py` is 137 lines. The behavior I verified:

### What the generator does

- Iterates JSON-Lines input. Skips lines that don't start with `{` and lines that fail `json.loads`. Tolerant parser — silent on garbage.
- Filters to `event == "exec_decision"`.
- For ALLOW: keys by `realpath` (string) using `dict.setdefault` — **first observation wins, all subsequent observations of the same `realpath` are silently dropped, including their dev/ino/sha256.**
- For BLOCK: appends to a list; no key, no dedup, no cross-reference to ALLOW.
- Emits YAML with **only the path strings** under `allowed_executables`. The internal metadata (sha256, dev, ino, raw_exe, first_line) is captured per-realpath but never written to the output. Only the sorted set of path strings reaches the policy.
- Optional `--include-blocked-summary` writes the BLOCK list to a separate JSON. This is the "preserved separately" claim.

### What the generator does NOT do

1. **No provenance check on the input.** The generator accepts any JSON file as audit input. There is no signature, no required filename, no required directory, no host-vs-container realpath sanity check. Anyone who can write a JSON file can dictate the policy. The runner script gates the input path (`--observe-run-root`), but the generator itself is unguarded.
2. **No ALLOW ∩ BLOCK reconciliation.** I crafted input where the same `realpath` appears as ALLOW (line 1) and BLOCK (line 2). The generator emitted that path in `allowed_executables` *and* recorded the BLOCK in `blocked.json`. The proof-memo's "blocked records are excluded from allowed_executables" reads as if BLOCK subtracts from ALLOW; it does not. The two sets are independent. In the natural Sprint 9 audit log there is no overlap, so the bug does not manifest — but the *invariant* the doc claims is not enforced. Crafted-input transcript:

   ```
   Input: ALLOW /usr/bin/cat (line 1), BLOCK /usr/bin/cat (line 2),
          ALLOW /usr/bin/rm (line 3)
   Generator output: allowed=[/usr/bin/cat, /usr/bin/rm], blocked=[{cat sha=bbb}]
   ```

   Real risk: an attacker who can append a single ALLOW record for a path the legitimate audit log later BLOCKed (e.g., `/usr/bin/touch`) gets that path silently into the policy because the BLOCK does not retract.

3. **No SHA cross-check.** When the same `realpath` appears with different sha256/dev/ino, only the first is retained internally and **none of it is emitted** anyway. Mitigated downstream by the guard: `scripts/policy/compile_policy.py` writes only the path; `add_policy_path` in `guard/usernotify_exec_guard.c` calls `realpath()` and stats the host file at policy load time, binding dev/ino at *that* moment. So SHA-rotation in the input log doesn't affect the runtime decision; the runtime decision is host-fs-state at policy load. This is a defensible chain, but the generator is not contributing identity binding — it's contributing path strings only.

4. **No `check_exists` propagation.** The generator does not call `compile_policy.py --check-exists`, and the workflow runner doesn't pass `--check-exists` either (line 137 of the runner). I verified that the generator + compiler will happily emit and accept `/etc/shadow`, `/a/path/with/no/file`, and `/usr/bin/rm` from a crafted log. Compile rc=0; output JSON contains the bogus paths. The guard's `add_policy_path` will then reject paths that don't `realpath()` cleanly at load time, so the fail-closed property survives — but only because of guard-side validation, not generator-side validation.

5. **NUL bytes:** if a crafted log ever embedded `\x00` in `realpath`, the YAML serializer accepts it but `compile_policy.py` rejects with `allowed_executables[0] contains NUL`. That fail-closed boundary holds.

6. **YAML injection via `realpath`:** I tested input with embedded newlines and YAML metacharacters in `realpath`. `yaml.safe_dump` properly quotes and escapes, and `yaml.safe_load` round-trips the scalar. Not a vector.

### Verdict on threat model

The generator is honest at the level of *what it observes*: ALLOW means "this path was observed allowed by the running guard in this run." It is not honest at the level of *who can produce the input*: anyone who can write a file the runner reads can dictate the generated policy. The "blocked records are excluded" wording overpromises. The doc says `review_required: true`, which is the right honest backstop, but the generator should either (a) actually subtract BLOCK from ALLOW when realpaths overlap, or (b) document explicitly that ALLOW and BLOCK are reported as independent sets and the human reviewer must reconcile.

---

## 5. Closed-Loop Verification

### Phase mapping (from runner reading)

| Phase | What it does | Verifiable |
|---|---|---|
| Observe | Reads `latest_demo.txt` from Sprint 9 to find an existing OpenHands run, then pulls `runtime_container_logs.combined` from inside that run. **No new observation is performed by Sprint 10.** Sprint 10 reuses the audit logs Sprint 9 already produced. | Yes — `OBSERVE_LOG` resolves to `proofs/sprint9_runs/sprint9-demo-20260501T040010Z/.../runtime_container_logs.combined`. |
| Generate | Calls `generate_policy_from_audit.py` with `--policy-id sprint10_observed_openhands_policy_v1 --include-blocked-summary blocked_records.json`. | Yes — preserved stdout `generate_policy.stdout`. |
| Review | **Automated assertions, no human-in-the-loop step.** A python heredoc asserts `/usr/bin/cat` is in `allowed`, `/usr/bin/rm` is not, and at least one BLOCK record has `raw_exe == "./python3"`. That's it. There's no diff display, no human gate, no sanity check on the rest of the 16 paths. | Yes — `generated_policy_assertions.stdout`. |
| Enforce | Calls Sprint 9's `run_openhands_guard_demo.sh --policy-yaml <generated>`. The Sprint 9 runner does its own compile, negative-test, and nested OpenHands run. The outer Sprint 10 runner then asserts `pass=14 fail=0` is in the inner `demo_summary.txt`. | Yes — preserved `enforce_demo.stdout` and the Sprint 9 demo summary. |

### Reproducibility

I independently re-derived the generator output from the preserved input log:

```
$ python3 scripts/policy/generate_policy_from_audit.py <combined.log> /tmp/observed.yaml --include-blocked-summary /tmp/blocked.json
{ "allowed_executables": 16, "blocked_records": 10, "total_exec_decisions": 130 }
```

Diff vs `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.yaml`: identical except for `policy_id`. Diff vs `blocked_records.json`: identical. The generator is deterministic on the input log.

I did not re-run the full Sprint 10 enforce loop end-to-end; that requires a live OpenAI key and Docker, and the existing preserved artifacts give a complete chain. The headline numbers `pass=8 fail=0` (outer), `pass=14 fail=0` (enforce), `pass=11 fail=0` (nested OpenHands) all read clean from the preserved files.

### Phase characterization

The "review" phase is the weakest link. It is three asserts on three known-good values; it does not show the human anything. In a CI-driven workflow where the agent is also the reviewer, the "human-in-the-loop" framing in `docs/POLICY_WORKFLOW.md` ("Review before enforcing") collapses. Worth tightening the doc to say: *"the workflow's automated review step asserts cat∈ALLOW, rm∉ALLOW, and ./python3∈BLOCKED; full human review of the 16 entries remains the operator's responsibility."*

---

## 6. What Verified Clean Independently

- Gate `6d91c21` landed before proof `ef9cb75` (~4 min 45 s gap).
- Guard source SHA `842a687b...` and binary SHA `1af638ca...` unchanged from Sprint 9 — confirmed by recomputing locally.
- `scripts/policy/generate_policy_from_audit.py` SHA `5f9a6b08...` matches proof memo.
- `scripts/demo/observe_generate_review_enforce.sh` SHA `c71986db...` matches.
- `scripts/policy/compile_policy.py` SHA `d2f6e853...` matches.
- 130 exec_decision records in input log; 16 unique ALLOW realpaths; BLOCK records: 4 `unresolved_executable_identity` (git from various paths), 4 `blocked_executable_identity` (`/usr/bin/touch` x2, `/usr/bin/grep` x2 from a `.bashrc` configuration probe by the OpenHands runtime), 2 `blocked_executable_identity` for the copied `./python3` (the prescribed test). 10 BLOCKs total — matches claim.
- Generated YAML reproducibly recreated; output is identical to the preserved artifact (modulo policy_id).
- Sprint 10 outer summary records `pass=8 fail=0`. The 8 cases are: `env_file`, `observe_log`, `generate_policy`, `compile_generated_policy`, `generated_policy_assertions`, `enforce_generated_policy`, `enforce_summary`, `secret_scan`. These cover, in order: env loaded, audit log found, generator ran, output YAML compiled, content asserts passed, enforce demo passed, enforce summary equals `pass=14 fail=0`, no API key leakage.
- Sprint 9 hand-rolled YAML has 23 paths; Sprint 10 generated has 16. The 7 missing from generated are all *unobserved-in-this-run* paths: `/usr/bin/env`, `/usr/bin/ls`, `/usr/bin/sh`, `/usr/bin/su`, `/usr/bin/true`, `/usr/bin/which`, `/usr/local/bin/poetry`, `/usr/local/bin/python3`, `/usr/local/venv/bin/python` (9 actually; `/usr/bin/which` reduces to `/usr/bin/which.debianutils` in observation, so the generated list has the resolved target the hand-rolled list lacks). I confirmed by grepping the audit log that none of these were ever exec'd by this prompt's run. The Sprint 9 hand-rolled list was over-broad relative to *this* OpenHands prompt; it may not be over-broad for *all* OpenHands prompts. The "minimal production policy" ceiling remains exactly that — minimal-for-this-flow, not minimal-for-OpenHands-in-general.
- BLOCK preservation: confirmed in `blocked_records.json` (10 entries with line numbers 11, 12, 13, 14, 96, 98, 99, 100, 130, 141).
- Repo visibility was not public at the time of the historical audit (gh repo view confirmed `"visibility":"PRIVATE"`).
- Preserved failed run `sprint10-policy-workflow-20260501T075952Z` exists with `pass=4 fail=1`. The cause memo (assertion expected `realpath=/usr/bin/rm`, actual recorded `raw_exe=./python3`) is honest and was correctly tightened.

---

## 7. New Findings or Attack Surfaces Specific to Sprint 10

### F-10-A (MEDIUM) — Generator's BLOCK exclusion is documented but not implemented as set difference

`docs/POLICY_WORKFLOW.md` says "the generated YAML intentionally includes only observed `ALLOW` executable identities. Observed `BLOCK` records are written to a separate JSON summary." The proof memo says "blocked records are excluded from allowed_executables." Both phrases imply BLOCK subtracts from ALLOW. The code does not do that subtraction. With overlap (which doesn't occur in the natural Sprint 9 log, but could in a longer or adversarially-shaped log), an ALLOW record for a path also seen as BLOCK lands in the policy.

Fix: in the generator, after the loop, subtract BLOCK realpaths from ALLOW realpaths and report any subtraction in the metadata block. Or: tighten the docs to "ALLOW and BLOCK are reported as independent observation sets; the reviewer is responsible for resolving overlaps."

### F-10-B (MEDIUM) — Generator has no input provenance discipline

Generator accepts any JSON file. No path-anchoring (e.g., "must be inside `proofs/sprint{N}_runs/`"), no required schema fingerprint, no signature check. Combined with F-10-A, this means anyone with write access to the host filesystem can dictate the next policy by appending or producing audit JSON. In a CI / multi-tenant scenario this matters; in a operator's lab it's notional.

Fix: at minimum, validate that the input path is under a known proofs directory or carries an expected `policy_id` field that matches the running guard's actual policy_id at observation time.

### F-10-C (LOW) — "Review" phase is automated, not human-gated

Three asserts on a known-good shape. Doesn't show the policy to a human. The doc's "Review before enforcing" framing is correct as guidance but the *workflow doesn't enforce it*. If a future Sprint 11 wants a true reviewer-in-the-loop, this needs to gate on an interactive yes/no or a signed approval file.

### F-10-D (LOW) — Sprint 10 outer wrapper has no preflight checks

Inherits cleanup from Sprint 9 partially. If `scripts/policy/generate_policy_from_audit.py` is missing or non-executable, the failure surfaces as a generic "policy generation failed" rather than a clear preflight FAIL. Cosmetic — Sprint 9's runner's preflight covers the enforce phase.

### F-10-E (LOW) — Local env-file path leaked into preserved command logs

`proofs/SPRINT10_COMMAND_LOG_20260501.md` and `proofs/sprint10_runs/.../command_log.txt` originally contained a host-specific env-file path. Sprint 9 cleanup F-9-A removed analogous strings from `docs/DEMO.md`. Sprint 10's runner accepts a generic `--env-file PATH`, so the runner itself is portable, but the preserved command-log artifacts inadvertently re-introduced a local env-file path into the public-facing artifact set. (Does not leak the env contents — only the path string.)

### F-10-F (informational) — Generator output discards SHA / dev / ino metadata

The generator's internal data structure captures `sha256`, `dev`, `ino`, `raw_exe`, and `first_line` per allowed path, but the YAML output emits only the sorted list of path strings. This is consistent with the existing policy schema (which `compile_policy.py` accepts), but it means the generator is not contributing *identity* — only *paths* — to the policy. The runtime guard rebinds dev/ino at load time. Not a bug in the current architecture, but a missed opportunity: the generator could emit a "supporting evidence" block (per-path observed sha/dev/ino, count of observations, first/last seen line) into `metadata` to make the human review more substantive. This would be a Sprint 11 polish.

---

## 8. F4 Deferral, Non-CmdRunAction, Public Bootstrap, Recorded Demo Gaps

All carried forward correctly in the proof memo's table:

| Item | Status |
|---|---|
| F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred and disclosed |
| Non-`CmdRunAction` paths | Out of scope |
| Public self-serve clone-and-run package | Still open |
| Recorded outreach video/asciinema | Still open |
| Full OpenHands web UI | Out of scope |
| Production-grade sandbox claim | Not allowed |

Nothing new in Sprint 10 closes any of these. Sprint 10 explicitly does not change F4 status; the guard source/binary are unchanged. The "public clone-and-run" gap is unaddressed and the F-10-E local-path leak slightly worsens it at the proof-artifact level (though not at the runner level).

---

## 9. Sprint 11 Prerequisites

If the goal is "ship-ready" rather than "demo-ready":

1. **Generator BLOCK ∩ ALLOW reconciliation** (F-10-A): trivial code change, important docs invariant.
2. **Provenance-checked audit input** (F-10-B): refuse to generate from logs outside `proofs/sprint{N}_runs/`, or require a manifest fingerprint.
3. **Real reviewer gate** (F-10-C): interactive `yes/diff/no` step, or signed-approval file gate.
4. **Public bootstrap** (carried from Sprint 9 F-9-A): documented venv/Docker setup, pinned image digest in `docs/POLICY_WORKFLOW.md` and `docs/DEMO.md` (not the mutable `:1.6.0-nikolaik` tag), and a README quickstart that does not require the operator's `.env` path.
5. **Recorded asciinema** (carried from Sprint 9 F-9-F): outreach artifact.
6. **Generator emits identity evidence in metadata** (F-10-F): per-path observed dev/ino/sha256/raw_exe/observation count to make human review meaningful.
7. **F4 closure or honest one-page memo** that stops being deferred forever.
8. **Non-`CmdRunAction` coverage** (FileRead/Write/IPython/Browse) to lift the "production sandbox" ceiling.

Items 1-3 are Sprint-10-cleanup items. Items 4-5 close out Sprint 9 outreach. Items 6-8 are architectural.

---

## 10. Honest Headline Tightening

**Current proof memo claim** (line 139):

> Sprint 10 adds an observe/generate/review/enforce workflow: real guard audit logs from the OpenHands demo are converted into reviewable YAML policy, observed BLOCK records are preserved separately, that YAML compiles to guard JSON, and the guided OpenHands demo reruns successfully under the generated policy while preserving the copied-`rm` block assertion.

**Tightened (recommended):**

> Sprint 10 adds an observe → generate → automated-shape-check → enforce workflow on the prepared lab machine: the Sprint 9 OpenHands run's audit log is converted into a path-string YAML allowlist of the 16 ALLOW realpaths observed in that specific run; the 10 observed BLOCK records are written to a separate JSON for human inspection; the YAML compiles to guard JSON; and the Sprint 9 guided OpenHands demo reruns under the generated policy with `pass=14 fail=0` outer / `pass=11 fail=0` nested. The "review" step is three automated assertions, not a human gate. The generator includes ALLOW realpaths and lists BLOCK records but does not subtract BLOCK from ALLOW; the natural Sprint 9 log has no overlap, but the invariant is not enforced. Generator inputs are not provenance-checked; anyone who can write the input JSON can dictate the policy. Guard source/binary unchanged. F4, non-`CmdRunAction`, public clone-and-run, and recorded-demo gaps are not closed.

That phrasing matches the artifacts and surfaces the load-bearing caveats.

---

## 11. Commands Used For This Audit

```bash
git log --diff-filter=A --pretty=format:'%h %ai %s' -- 'proofs/SPRINT10*GATE*'
git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md

# Read all key files
cat proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md
cat proofs/SPRINT10_GATE_20260501.md
cat scripts/policy/generate_policy_from_audit.py
cat scripts/demo/observe_generate_review_enforce.sh
cat docs/POLICY_WORKFLOW.md
cat policy/examples/openhands_action_server.yaml
cat scripts/policy/compile_policy.py
cat scripts/demo/run_openhands_guard_demo.sh
cat proofs/AUDIT_20260501_sprint9_independent_review_orchestrator_pass2.md
cat proofs/SPRINT9_POST_AUDIT_CLEANUP_20260501.md
cat proofs/SPRINT10_COMMAND_LOG_20260501.md

# Verify SHAs
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
  scripts/policy/generate_policy_from_audit.py \
  scripts/demo/observe_generate_review_enforce.sh \
  scripts/policy/compile_policy.py

# Inspect preserved artifacts
cat proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/workflow_summary.txt
cat proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.yaml
cat proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/blocked_records.json
cat proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.json
cat proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/command_log.txt
cat proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z/workflow_summary.txt
cat proofs/sprint9_runs/sprint9-demo-20260501T080016Z/demo_summary.txt
cat proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z/replay_summary.txt

# Re-derive generator output independently
LOG=proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined
python3 scripts/policy/generate_policy_from_audit.py "$LOG" /tmp/audit_a/replay/observed.yaml \
  --include-blocked-summary /tmp/audit_a/replay/blocked.json --policy-id auditor_a_replay
python3 scripts/policy/compile_policy.py /tmp/audit_a/replay/observed.yaml /tmp/audit_a/replay/observed.json
diff /tmp/audit_a/replay/observed.yaml proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.yaml
diff /tmp/audit_a/replay/blocked.json proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/blocked_records.json

# Threat-model probes
# 1. ALLOW + BLOCK same realpath
python3 scripts/policy/generate_policy_from_audit.py /tmp/audit_a/mixed.log /tmp/audit_a/mixed.yaml \
  --include-blocked-summary /tmp/audit_a/mixed_blocked.json
# Result: /usr/bin/cat appears in allowed AND blocked.

# 2. Crafted JSON with arbitrary realpath
python3 scripts/policy/generate_policy_from_audit.py /tmp/audit_a/attack.log /tmp/audit_a/attack.yaml
python3 scripts/policy/compile_policy.py /tmp/audit_a/attack.yaml /tmp/audit_a/attack.json
# Result: /etc/shadow, /a/path/with/no/file, /usr/bin/rm all accepted by generator+compiler.

# 3. NUL byte injection
python3 scripts/policy/compile_policy.py /tmp/audit_a/nul.yaml /tmp/audit_a/nul.json
# Result: compile rejects with "contains NUL" — fail-closed boundary holds.

# 4. YAML injection via realpath (newlines in scalar)
# Result: yaml.safe_dump properly quoted; not a vector.

# Count exec_decision records and unique realpaths in input log
grep -c 'exec_decision' "$LOG"           # 130
grep '"decision":"ALLOW"' "$LOG" | python3 -c '...'  # 16 unique
grep '"decision":"BLOCK"' "$LOG" | python3 -c '...'  # 3 distinct realpaths + <unresolved>

# Compare hand-rolled vs generated
diff <(grep '^  -' policy/examples/openhands_action_server.yaml | sed 's/^  - //' | sort) \
     <(grep '^- ' proofs/sprint10_runs/.../openhands_observed.allow.yaml | sed 's/^- //' | sort)

# Check repo visibility
gh repo view blazingRadar/agent-exec-guard-lab --json visibility   # PRIVATE

# Cleanup
rm -rf /tmp/audit_a
```

---

## Files

- This audit: `proofs/AUDIT_20260501_sprint10_independent_review_a.md`
- Sprint 10 proof memo: `proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md`
- Sprint 10 gate: `proofs/SPRINT10_GATE_20260501.md`
- Sprint 10 command log: `proofs/SPRINT10_COMMAND_LOG_20260501.md`
- Generator: `scripts/policy/generate_policy_from_audit.py` (sha256 `5f9a6b08...`)
- Workflow runner: `scripts/demo/observe_generate_review_enforce.sh` (sha256 `c71986db...`)
- Compiler: `scripts/policy/compile_policy.py` (sha256 `d2f6e853...`)
- Workflow doc: `docs/POLICY_WORKFLOW.md`
- Passing run: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/`
- Preserved failed run: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z/`
- Enforce rerun: `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/`
- Nested OpenHands: `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z/`
- Source audit log: `proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined`
- Sprint 9 cleanup memo: `proofs/SPRINT9_POST_AUDIT_CLEANUP_20260501.md`
- Sprint 9 audit pass 2: `proofs/AUDIT_20260501_sprint9_independent_review_orchestrator_pass2.md`
- Guard source: `guard/usernotify_exec_guard.c` (sha256 `842a687b...`, unchanged from Sprint 8)
- Guard binary: `bin/usernotify_exec_guard` (sha256 `1af638ca...`, unchanged from Sprint 8)
