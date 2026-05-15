# Sprint 10 — Auditor B Independent Review

Date: 2026-05-01
Auditor: Auditor B (independent of Auditor A; no coordination).
Posture: adversarial review of the Sprint 10 observe/generate/review/enforce policy workflow, with live re-derivation against preserved artifacts and crafted-input probes.
Source of record: live commands; preserved Sprint 10 run artifacts; the generator and runner source.

---

## 1. Audit Question and Source of Record

**Question.** Does Sprint 10 honestly add an observe/generate/review/enforce closed loop on top of Sprint 9, with a generator whose threat model is correctly described, without regressing Sprint 9 cleanup learnings, without changing the guard?

**Source of record:**

- Generator: `scripts/policy/generate_policy_from_audit.py` (sha256 `5f9a6b08...`).
- Runner: `scripts/demo/observe_generate_review_enforce.sh` (sha256 `c71986db...`).
- Compiler reused: `scripts/policy/compile_policy.py` (sha256 `d2f6e853...`).
- Doc: `docs/POLICY_WORKFLOW.md`.
- Gate: `proofs/SPRINT10_GATE_20260501.md` (`6d91c21`).
- Proof memo: `proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md` (`ef9cb75`).
- Command log: `proofs/SPRINT10_COMMAND_LOG_20260501.md`.
- Final passing run: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/`.
- Preserved failed run: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z/`.
- Inner enforce demo run: `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/`.
- Inner OpenHands run: `.../openhands_runs/sprint8-frontier-agent-20260501T080016Z/`.
- Observed source log: `proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined`.

---

## 2. Verdict

**Sprint 10 substantively delivers the closed loop end-to-end on the prepared lab machine, but the generator's threat model is silently weaker than the proof memo and POLICY_WORKFLOW.md imply, and one safety claim ("blocked records are excluded from allowed_executables") is not actually enforced by the generator.**

The headline "real audit logs → reviewable YAML → compiled JSON → guarded enforce rerun" reproduces from preserved artifacts. The unchanged-guard claim holds. The pass=8 outer / pass=14 enforce / pass=11 nested triple matches the proof memo. But the generator inherits an *implicit* trust assumption — its input is a guard audit log produced by a trusted prior run — that is documented neither in the generator's source comments nor in `docs/POLICY_WORKFLOW.md`. Crafted-input probes show the generator is happy to allowlist arbitrary paths (including `/usr/bin/rm`) if a malicious or accidentally-merged audit log claims they were ALLOW'd, and to silently retain a realpath in the allowlist even when the same realpath is concurrently BLOCK'd in the input.

This does not invalidate the sprint claim as scoped to "observe a trusted prior run, generate a reviewable policy, rerun enforce." It does invalidate any reading of "the generator excludes blocked records," which is what the embedded note string says.

---

## 3. Discipline Check

### Pre-registration

Verified live:

```text
6d91c21 2026-05-01 00:58:07 -0700 Pre-register Sprint 10 policy workflow gate
ef9cb75 2026-05-01 01:02:52 -0700 Sprint 10 observed policy workflow
```

Gate landed ~4 min 45 s before implementation. Order is correct. Tighter than Sprint 9's ~8 minutes but inside the lab's discipline window.

### Sprint 9 cleanup carried forward

Reading `observe_generate_review_enforce.sh`:

| Sprint 9 cleanup item | Sprint 10 status |
|---|---|
| Self-locating `ROOT` (no hardcoded `/home/blazingradar`) | Yes — `ROOT="${AEG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"` (line 4) |
| EXIT trap with cleanup | Yes — `trap finish EXIT` (line 77) emits aggregate `pass=N fail=N` |
| Aggregate `pass=N fail=N` row | Yes — emitted by `finish()` |
| Preflight checks | Partial — env file existence is checked, but the existence of `scripts/policy/generate_policy_from_audit.py` and `scripts/policy/compile_policy.py` is not verified before invocation. (The inner Sprint 9 demo it invokes does its own preflight, so docker / OpenHands source / replay harness are still checked downstream.) |
| Post-run container cleanup | Delegated to the Sprint 9 demo's own EXIT trap. Sprint 10 runner does not invoke any cleanup itself. Acceptable but worth naming. |
| README status sync | Yes — `README.md:23` says "Sprint 10 observe/generate/review/enforce workflow passed". |

No regressions on the Sprint 9 portability fixes.

### Carry-forward Open Items

Sprint 10 proof memo §"Carry-Forward Open Items" enumerates: public clone-and-run, recorded video/asciinema, F4 CONTINUE TOCTOU, non-`CmdRunAction`, full Web UI, production sandbox claim. All present. Audit history index also updated.

Discipline check passes.

---

## 4. Generator Threat-Model Evaluation (load-bearing)

This is the load-bearing finding for Sprint 10. I read `generate_policy_from_audit.py` line-by-line and probed with crafted JSON inputs.

### What the generator actually does

For each line in the input file that parses as JSON and has `event == "exec_decision"`:

- If `decision == "ALLOW"` and `realpath` is a string starting with `/`, add it to the `allowed` dict keyed by `realpath`, taking the *first* observed identity (`setdefault`, lines 54–65).
- If `decision == "BLOCK"`, append the record to a separate `blocked` list (lines 66–75).

It then writes a YAML with `allowed_executables` = sorted `realpath` keys and (optionally) a JSON file with the blocked records.

### What the generator does NOT do

#### Threat-model gap 1: no provenance check on the input audit log

The generator treats any JSON file passed on the command line as authoritative. There is no check that the input came from the Sprint 8/9 harness, that it was produced by the guard binary at `bin/usernotify_exec_guard` (sha256 `1af638ca…`), that the records are signed, or that the audit-log file path is under a trusted prefix. Anyone who can hand the user a crafted JSON file and convince them to point the generator at it can produce any policy they want.

This is the first rule of trusted-computing for log-driven configuration: the log is part of the trust boundary. The generator does not enforce any boundary.

`docs/POLICY_WORKFLOW.md` does not mention this. Its "Review Boundary" section says "the generated YAML intentionally includes only observed `ALLOW` executable identities" — which is *exactly* the assumption an attacker would exploit.

#### Threat-model gap 2: BLOCK records do NOT remove a realpath from the allowlist

I probed with this synthetic input:

```jsonl
{"event":"exec_decision","decision":"ALLOW","realpath":"/usr/bin/cat","raw_exe":"/usr/bin/cat","sha256":"abc","dev":1,"ino":1}
{"event":"exec_decision","decision":"ALLOW","realpath":"/bin/sh","raw_exe":"/bin/sh","sha256":"def","dev":1,"ino":2}
{"event":"exec_decision","decision":"ALLOW","realpath":"/usr/bin/nc","raw_exe":"/usr/bin/nc","sha256":"hijack1","dev":2,"ino":3}
{"event":"exec_decision","decision":"BLOCK","realpath":"/usr/bin/nc","raw_exe":"/usr/bin/nc","sha256":"hijack1","reason":"blocked_executable_identity"}
{"event":"exec_decision","decision":"ALLOW","realpath":"/usr/bin/cat","raw_exe":"/usr/bin/cat","sha256":"DIFFERENT","dev":1,"ino":1}
```

Result: `allowed_executables` = `[/bin/sh, /usr/bin/cat, /usr/bin/nc]`, `blocked_count = 1`.

Both `/usr/bin/nc` ALLOW and `/usr/bin/nc` BLOCK records are present, the BLOCK is recorded in the blocked summary, and `/usr/bin/nc` is *also* in the allowlist. The note string written into the YAML metadata says:

```
note: Generated from observed ALLOW records. Review before enforcing; blocked records are excluded from allowed_executables.
```

The second clause is **false**. A realpath that has BOTH an ALLOW record AND a BLOCK record in the same input is added to the allowlist, not excluded. Today's Sprint 10 demo case happens to be safe because the renamed `rm` block has `realpath=/lab/.../workspace/python3` (a workspace path, never observed in ALLOW), so the case never arises in the proof. But the generator's behavior contradicts its own self-description.

This is the cleanest correctness defect in Sprint 10. It is also the most embarrassing one if cited externally: the doc says the generator does X, the generator does not do X.

#### Threat-model gap 3: dedupe key is `realpath` string only — no `(realpath, dev, ino, sha256)` tuple

Line 54: `allowed.setdefault(realpath, {...})`. Three implications:

1. If the same path is observed under different (`dev`, `ino`) (e.g. the binary at `/usr/bin/cat` was replaced between observations), the generator silently keeps the *first* observation's metadata and discards the second. SHA mismatches across observations are not surfaced to the reviewer.
2. The guard's runtime decision uses identity — `(dev, ino, sha256)` — but the generator only emits the `realpath` to the compiled JSON. So the policy enforced by the guard is "any executable whose realpath matches one of these strings." A reviewer reading the YAML cannot tell whether the binary at `/usr/bin/cat` they're authorizing today is the same as the one observed during generation.
3. Consequently, an adversary who can replace `/usr/bin/cat` between policy generation and enforce time can run arbitrary code under the generated policy. (This is the same TOCTOU class that F4 already flags for the guard's CONTINUE-mode optimization, surfaced now on the policy-distribution side.)

The compiler does not close this either: `compile_policy.py:43-54` validates the path is absolute, NUL-free, deduped, and (with `--check-exists`) exists and is executable, but does not retain or check `(dev, ino, sha256)` from the observed run.

Net: the generated policy is a path-string allowlist, not an identity allowlist. The guard at runtime still enforces the full identity check from the binary's own internal state, so this is not a runtime bypass via the generator output. But the generator's *advertised* function — turning observed identities into a reusable policy — discards the identity dimensions before writing the policy.

#### Threat-model gap 4: no canonicalization or realpath sanity

I probed with paths containing `..`, embedded newlines, the bare `/`, and trailing whitespace. The generator stores them verbatim (raw newlines included); the compiler accepts everything except an empty string and non-absolute paths. A YAML with `/usr/bin/../bin/cat` and the bare `/` compiles cleanly. The bare `/` is harmless because it can't match a realpath of any executable, but `/usr/bin/../bin/cat` would match no realpath either (the guard normalizes to `/usr/bin/cat`), so this is more "garbage in / garbage out" than exploitable. Still, neither generator nor compiler runs `os.path.realpath()` against the policy entries, so reviewer-confusing inputs survive end-to-end.

#### Threat-model gap 5: `policy_id` is taken from a CLI flag with no validation

`--policy-id` accepts arbitrary strings. `yaml.safe_dump` properly escapes them, so YAML injection is not feasible. But there is no namespacing or required prefix, so a generated policy and a hand-rolled policy with colliding `policy_id` values would be indistinguishable in audit logs.

### Summary

The generator inherits the trust assumptions of the observation. It is safe under the assumption that the input audit log is the unmodified product of the trusted guard binary applied to a trusted run. None of those assumptions are documented or checked. This is fine for a prepared lab where the user runs the closed loop end-to-end on their own machine. It is *not* fine if the generator is positioned as a reviewable artifact pipeline, because the YAML it emits is the artifact a human reviewer is supposed to trust.

---

## 5. Closed-Loop Verification

### Phase analysis

Reading `observe_generate_review_enforce.sh` line-by-line:

- **Observe.** Lines 98–103: read `$OBSERVE_RUN_ROOT` from CLI, otherwise pull `proofs/sprint9_runs/latest_demo.txt` and pick the latest `openhands_runs/<run>/` subdir. Line 110: `OBSERVE_LOG="$OBSERVE_RUN_ROOT/runtime_container_logs.combined"`. There is **no fresh observation phase** — the runner consumes a previously-produced Sprint 9/Sprint 8 run's container logs. The closed loop is "load a prior trusted run's audit log → generate → enforce a fresh demo," not "observe → generate → enforce → re-observe → repeat."
- **Generate.** Lines 124–134: invoke the generator with the observed log, output YAML and blocked-summary JSON.
- **Review.** Implicit. The runner runs an automated assertion (lines 145–170) against the generated YAML and blocked summary: `cat in allowed`, `rm not in allowed`, `at least one BLOCK record has raw_exe == "./python3"`. There is no human-review step in the runner; "review" exists only in `docs/POLICY_WORKFLOW.md` as a workflow concept.
- **Enforce.** Lines 173–181: invoke `run_openhands_guard_demo.sh --policy-yaml <generated>`, which compiles the generated YAML and runs the Sprint 8 frontier-model harness against it.
- **Verify.** Line 185: `grep -q 'pass=14 fail=0' "$ENFORCE_RUN_ROOT/demo_summary.txt"` — string match for hardcoded count, brittle but correct for this snapshot.

### Reproduction

Docker is reachable:

```text
$ sg docker -c "docker info" | head -3
Client: Docker Engine - Community
 Version:    29.1.3
```

A live `bash scripts/demo/observe_generate_review_enforce.sh --env-file …` would burn a fresh OpenAI gpt-5.2 frontier-model run. I did not execute this — both because it requires the operator's API key (not available to the audit) and because the proof's reproduction discipline already preserves the artifacts. Verification was done by reading preserved artifacts.

### What the preserved artifacts confirm

- `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/workflow_summary.txt`: 8 PASS lines + `pass=8 fail=0`.
- `proofs/sprint10_runs/.../generated/openhands_observed.allow.yaml`: 16 entries.
- `proofs/sprint10_runs/.../generated/blocked_records.json`: 10 entries (4 unresolved-git lookups + 2 touch + 2 grep + 2 copied-`rm`).
- `proofs/sprint10_runs/.../generated/openhands_observed.allow.json`: same 16 entries.
- `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/policy/openhands_action_server.allow.json`: identical 16 entries — confirms the enforce run actually used the generated policy, not the hand-rolled one.
- `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/demo_summary.txt`: `pass=14 fail=0`.
- `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z/replay_summary.txt`: `pass=11 fail=0`, including `guard_blocked_python3` PASS and `trajectory_denial_structured` PASS at `exit_code=126`.
- `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/sha256s.txt`: guard source `842a687b…`, binary `1af638ca…` — unchanged from Sprint 9.

The closed loop reproduces from artifacts. The pass=8 / pass=14 / pass=11 triple matches the proof memo.

### Bootstrap subtlety

The runner uses `latest_demo.txt` to find the observed run, but the inner `run_openhands_guard_demo.sh` overwrites `latest_demo.txt` early (line 80 of that script) with the *new* enforce run. The Sprint 10 runner reads the file once before triggering the new demo, so the bootstrap works. This is fragile — if the order of operations changed, or if a parallel demo were running, the observed-run pointer could be the run currently being created. Worth a comment in the script.

The "first" observation root is the Sprint 9 040010Z run, which itself was produced under the *hand-rolled* Sprint 9 policy (`policy_id=sprint9_openhands_action_server_allowlist_v1` in the audit log). So Sprint 10's closed loop is "observe-under-Sprint-9 → generate → enforce-under-Sprint-10-generated." It is not yet "observe-under-generated → re-generate → re-enforce" (i.e. fixed-point convergence). Whether to call this "closed" is a definitional question; my reading is that it closes one cycle, not a stable iteration.

---

## 6. What Verified Clean Independently

- Gate `6d91c21` precedes proof `ef9cb75` by ~4 min 45 s in git timeline.
- Guard source sha256 `842a687b…` and binary sha256 `1af638ca…` unchanged from Sprint 9.
- Generator sha256 `5f9a6b08…`, runner sha256 `c71986db…`, compiler sha256 `d2f6e853…` all match proof memo §Hashes.
- Generator runs as a clean Python 3 + PyYAML script; no shell-out, no external subprocess.
- Outer Sprint 10 workflow_summary records 8 PASS / 0 FAIL with named cases: env_file, observe_log, generate_policy, compile_generated_policy, generated_policy_assertions, enforce_generated_policy, enforce_summary, secret_scan.
- Inner Sprint 9 enforce demo records 14 PASS / 0 FAIL.
- Inner Sprint 8 OpenHands run records 11 PASS / 0 FAIL with structured trajectory denial at `exit_code=126` and the guard blocking `./python3` (renamed `/usr/bin/rm`).
- The 16 generated entries are an exact subset of the union of (Sprint 9's 23 hand-rolled entries) ∪ {`/usr/bin/dash`, `/usr/bin/which.debianutils`}. The two new entries are debian-alternatives realpath resolutions of `/usr/bin/sh` → `/usr/bin/dash` and `/usr/bin/which` → `/usr/bin/which.debianutils`, which is what the guard sees after symlink resolution. So the generated policy is genuinely *what was actually executed*, not a re-typed list.
- The 10 BLOCK records reconcile: 4 unresolved-git path-search misses (early in the run, before `/usr/bin/git` is found) + 2 ALLOW-by-policy-after-block reattempts of `touch`/`grep` that the run never authorized + the 2 copied-`rm` blocks at lines 130/141. Consistent with the prior Sprint 8 run pattern.
- Preserved failed run `sprint10-policy-workflow-20260501T075952Z` records `pass=4 fail=1` with the assertion error correctly diagnosed in the command log: the original assertion expected `realpath=/usr/bin/rm`, the audit correctly recorded the workspace realpath. The fix tightened the assertion, not the guard. Honest correction.
- Carry-forward Open Items table present in the proof memo with all six items. Audit history index updated to add Sprint 10. README updated.
- `/tmp` not used for retained artifacts; smoke-test outputs were removed (per command log §Smoke Test).
- API key hygiene: `set -a; . "$ENV_FILE"; set +a` pattern, secret_scan PASS over Sprint 10 run dir, no `sk-`/`sk-proj-` patterns.
- Self-locating `ROOT`, EXIT trap, aggregate `pass=N fail=N` all present (Sprint 9 cleanup carried forward).

---

## 7. New Findings or Attack Surfaces Specific to Sprint 10

### F-10-A (HIGH on the documentation, MEDIUM on the runtime) — generator's `note` field overstates exclusion of blocked records

The YAML metadata note string says "blocked records are excluded from allowed_executables." Probing shows: a realpath that appears in BOTH an ALLOW and a BLOCK record will be in `allowed_executables`. The note is false. This does not affect today's demo because the renamed-`rm` block has a workspace realpath that never appears as an ALLOW. It will mislead any reviewer who reads the note as a guarantee.

**Fix:** either change the generator to subtract realpaths that appear in any BLOCK record (subject to a careful definition — same realpath under different SHA could legitimately be both), or change the note string to "blocked records are recorded separately and are NOT automatically subtracted from allowed_executables; review them before approving."

### F-10-B (MEDIUM) — generator dedupes by realpath only, discards `(dev, ino, sha256)`

The guard's runtime check is identity-based. The policy emitted by the generator is path-based. The reviewer reading the generated YAML sees only paths, not the identities that were observed. If `/usr/bin/cat` is replaced between generation and enforce, the policy still authorizes it. This is a TOCTOU adjacency — not a guard bypass per se, but a regression in the reviewer's information.

**Fix:** include observed `(dev, ino, sha256)` in the YAML (commented or under a separate `observed_identities` block) so a reviewer can see them. Optionally, generate a JSON policy that the guard consumes with identity-pinning instead of path-only.

### F-10-C (MEDIUM) — input audit log has no provenance check

The generator accepts any JSON file. There is no signature, no required path prefix (e.g. "must be under `proofs/sprint*_runs/`"), no validation that the policy_id field across records is consistent, no check that the audit log matches a guard-binary-claimed origin. An adversary who can write a JSON file and convince the user to point the generator at it can produce arbitrary policies.

**Fix:** at minimum, validate that all records have a consistent `policy_id` and that the `policy_id` matches a known prefix; ideally, sign audit logs with the guard binary's key (out of scope for this sprint, but worth documenting as a future requirement).

### F-10-D (LOW) — generator's note about review is in the YAML, not enforced anywhere

`metadata.review_required: true` is written as data, not as a compile-time check. `compile_policy.py` does not look at it. There is no "policy must be marked reviewed by a human" gate before enforcement. The runner just runs the demo against any compiled policy.

**Fix:** add an optional flag to the compiler that refuses generated policies unless `metadata.review_approved: true` is set explicitly by a human. Today this is a pure-honor-system field.

### F-10-E (LOW) — no canonicalization of realpath inputs

`/usr/bin/../bin/cat`, the bare `/`, and paths with embedded newlines all survive generation and compilation. None are exploitable today (the guard normalizes its own runtime realpath comparisons), but they would confuse a human reviewer.

**Fix:** add `os.path.realpath(path) == path and os.path.isabs(path)` validation in the generator's filter, and/or in the compiler with a flag.

### F-10-F (LOW) — runner has partial preflight only

The Sprint 10 runner checks env-file existence and observe-log existence, but does not preflight that the generator script and compiler script exist. They will fail noisily but not as a clean PASS/FAIL preflight record. Cosmetic relative to Sprint 9's pattern but a small drift.

**Fix:** add `[ -x "$ROOT/scripts/policy/generate_policy_from_audit.py" ]` and similar for compile_policy.py, mirroring the Sprint 9 demo's preflight pattern.

### F-10-G (LOW) — assertion is brittle to count drift

`grep -q 'pass=14 fail=0'` in line 185 hardcodes the inner Sprint 9 demo's pass count. If the Sprint 9 demo adds or removes a check, this assertion silently fails or silently passes. Better: assert `^pass=[0-9]+ fail=0$` and verify the count separately.

**Fix:** match `fail=0` for status, and assert pass-count separately if needed.

### F-10-H (process) — runner does not pass `--env-file` to the inner demo

Sprint 10 runner sources the env file into its own environment, so `OPENAI_API_KEY` propagates to the inner demo via inheritance. This works but is implicit; a reader of the runner could miss that the inner demo's `--env-file` parameter is unused on this path. Document it or pass it explicitly.

---

## 8. F4 Deferral, Non-CmdRunAction, Public-Bootstrap, Recorded-Demo Gaps

All four named honestly in the Sprint 10 proof memo:

- **F4 CONTINUE TOCTOU** — "Deferred and disclosed."
- **Non-`CmdRunAction` paths** — "Out of scope."
- **Public self-serve clone-and-run package** — "Still open."
- **Recorded outreach video/asciinema** — "Still open."

Sprint 10 does not change any of these. The guard binary and source are unchanged.

The public-bootstrap gap: Sprint 10 runner does inherit Sprint 9's self-locating ROOT, but it still depends on the runtime artifacts of a prior Sprint 9 run (it reads `latest_demo.txt` and the preserved Sprint 9 audit log). A fresh clone with no prior Sprint 9 run cannot bootstrap Sprint 10 without first running Sprint 9. So Sprint 10 inherits Sprint 9's gap, plus a small ordering dependency.

---

## 9. Sprint 11 Prerequisites OR What Remains for "Ship-Ready"

Sprint 10 is the *demo-ready* polish on top of Sprint 9's productized loop. To call this "ship-ready" — i.e., a reviewer or external party can clone the public repo, run one command, and have the policy-generation loop reproduce on their machine — the lab still needs:

### Hard prerequisites (must-have for any external claim)

1. **Fix F-10-A.** Either make the note true by actually excluding BLOCK realpaths, or rewrite the note. Today the YAML self-description is incorrect.
2. **Public-bootstrap path** (carry-forward from Sprint 9). Runner script that clones OpenHands at the pinned commit, builds the venv, builds the guard binary, and runs the loop. Until this exists, "clone-and-run" is not honest.
3. **Recorded asciinema/video** of one full closed-loop run. Outreach artifact, named in carry-forward.
4. **Document the generator's actual threat model** in `docs/POLICY_WORKFLOW.md`. Specifically:
   - "the generator does not validate the provenance of the input audit log";
   - "the generator does not subtract BLOCK realpaths from the allowlist";
   - "the generator emits path-based policy, not identity-pinned policy";
   - "the review step is implicit — there is no enforced human-approval gate before enforcement."

### Soft prerequisites (would tighten the claim)

5. **Identity-pinning in the generated policy**, addressing F-10-B.
6. **Realpath canonicalization** in the generator, addressing F-10-E.
7. **Preflight all script dependencies** in the Sprint 10 runner, addressing F-10-F.
8. **Robust enforce-summary assertion**, addressing F-10-G.
9. **Audit-log signature scheme** (much bigger, probably its own sprint) so the generator can reject untrusted JSON.

### Architectural items beyond demo readiness

10. **F4 CONTINUE TOCTOU closure** — long deferred, still load-bearing for any production claim.
11. **Non-`CmdRunAction` coverage** — out of scope for the current path, named honestly.

If Sprint 11 picks one item, F-10-A (the false note string) is the cheapest, highest-value fix because it removes a self-contradiction in shipped artifacts. Sprint 11 should also pick the public-bootstrap path because it unblocks all the outreach claims that have been deferred since Sprint 9.

---

## 10. Honest Headline for Sprint 10

The current claim in the proof memo:

> Sprint 10 adds an observe/generate/review/enforce workflow: real guard audit logs from the OpenHands demo are converted into reviewable YAML policy, observed BLOCK records are preserved separately, that YAML compiles to guard JSON, and the guided OpenHands demo reruns successfully under the generated policy while preserving the copied-`rm` block assertion.

This is *almost* accurate but contains one subtle overclaim. "Observed BLOCK records are preserved separately" is true (they are written to `blocked_records.json`). But the YAML's own metadata note says they are "excluded from allowed_executables," which is **not** true at the generator level — only true contingent on the observation having no realpath collision between ALLOW and BLOCK.

Tightened headline I would accept:

> Sprint 10 adds an observe/generate/review/enforce workflow on the prepared lab machine: the generator converts a prior trusted run's guard audit log into a reviewable YAML policy of observed ALLOW realpaths, writes observed BLOCK records to a separate JSON for human review, the YAML compiles to guard JSON, and the OpenHands demo reruns successfully under the generated policy at `pass=14 fail=0` outer / `pass=11 fail=0` nested. The generator does not validate the provenance of its input audit log, does not subtract BLOCK realpaths from the allowlist, and emits a path-based policy rather than an identity-pinned one; the workflow is therefore safe under the assumption that the input audit log is the unmodified product of a trusted prior guard run.

That tightened version preserves what the artifacts actually prove and explicitly bounds the trust assumption the generator inherits.

For audit-history-index purposes, the strongest *short* claim should also retire "blocked records are excluded from allowed_executables" wording: that phrase appears today in the generated YAML's metadata note string and is the most likely place the inaccuracy will leak into outreach material.

---

## 11. Commands Used For This Audit

```bash
# Repo state and pre-registration
ls -la /home/blazingradar/agent-exec-guard-lab/
cd /home/blazingradar/agent-exec-guard-lab && git log --oneline -20
git log --diff-filter=A --pretty=format:'%h %ai %s' -- 'proofs/SPRINT10*GATE*'
git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md
git log --pretty=format:'%h %ai %s' 6d91c21^..ef9cb75
git ls-remote origin refs/heads/main

# Read key files
# (Read tool used for: SPRINT10_POLICY_WORKFLOW_PROOF, SPRINT10_GATE,
#  generate_policy_from_audit.py, observe_generate_review_enforce.sh,
#  POLICY_WORKFLOW.md, SPRINT10_COMMAND_LOG, AUDIT_20260501_sprint9_…_pass2.md,
#  SPRINT9_POST_AUDIT_CLEANUP, run_openhands_guard_demo.sh, compile_policy.py,
#  README.md, AUDIT_HISTORY_INDEX, generated yaml/json/blocked_records,
#  workflow_summary.txt, sha256s.txt, demo_summary.txt, replay_summary.txt)

# Hash verification
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
  scripts/policy/generate_policy_from_audit.py \
  scripts/demo/observe_generate_review_enforce.sh \
  scripts/policy/compile_policy.py

# Sprint 9 vs Sprint 10 policy diff
diff <(grep -E "^\- /" policy/examples/openhands_action_server.yaml | sort) \
     <(grep -E "^\- /" proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.yaml | sort)
comm -23 ... # paths only in Sprint 9 hand-rolled
comm -13 ... # paths only in Sprint 10 generated

# Audit log analysis
wc -l proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined
grep -c '"event":"exec_decision"' …/runtime_container_logs.combined
# Python one-liner counting unique ALLOW realpaths and BLOCK records

# Probe 1: BLOCK + ALLOW collision
# /tmp/sprint10_probe_attack.jsonl with five crafted records
scripts/policy/generate_policy_from_audit.py /tmp/sprint10_probe_attack.jsonl /tmp/sprint10_attack.yaml \
  --include-blocked-summary /tmp/sprint10_attack_blocked.json
# Result: /usr/bin/nc in allowed AND in blocked

# Probe 2: pure attacker-controlled input
# /tmp/sprint10_pure_attack.jsonl with /usr/bin/wget and /tmp/evil ALLOW
# Result: both added to allowed_executables

# Probe 3: rm spoofing
# /tmp/sprint10_rm_attack.jsonl with /usr/bin/rm ALLOW
# Result: /usr/bin/rm in allowlist

# Probe 4: weird realpaths via Write tool to /tmp/sprint10_weird.jsonl
scripts/policy/generate_policy_from_audit.py /tmp/sprint10_weird.jsonl /tmp/sprint10_weird.yaml
scripts/policy/compile_policy.py /tmp/sprint10_weird.yaml /tmp/sprint10_weird.json
# Result: bare "/", "/usr/bin/../bin/cat", path with embedded newline all compile

# Probe 5: policy_id YAML injection
scripts/policy/generate_policy_from_audit.py /tmp/sprint10_pure_attack.jsonl /tmp/sprint10_pa.yaml \
  --policy-id "evil: bad: 'quote\""
# Result: properly escaped by yaml.safe_dump

# Probe 6: multi-run merge
scripts/policy/generate_policy_from_audit.py /tmp/sprint10_combined.jsonl /tmp/sprint10_combined.yaml
# Result: ALLOW realpaths from both runs naively merged

# Docker reachability
sg docker -c "docker info" | head -3
sg docker -c "docker ps" | head -5

# Cleanup
rm -f /tmp/sprint10_*.jsonl /tmp/sprint10_*.yaml /tmp/sprint10_*.json
rmdir /tmp/sprint10_traversal_out
```

All `/tmp` artifacts produced for probing were removed at the end of the audit.

---

## Files Cited

- This audit: `proofs/AUDIT_20260501_sprint10_independent_review_b.md`
- Sprint 10 gate: `proofs/SPRINT10_GATE_20260501.md`
- Sprint 10 proof memo: `proofs/SPRINT10_POLICY_WORKFLOW_PROOF_20260501.md`
- Sprint 10 command log: `proofs/SPRINT10_COMMAND_LOG_20260501.md`
- Sprint 10 final run: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/`
- Sprint 10 preserved failed run: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z/`
- Sprint 10 inner enforce run: `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/`
- Sprint 10 inner OpenHands run: `proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z/`
- Sprint 10 observed source log: `proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined`
- Generator: `scripts/policy/generate_policy_from_audit.py` (sha256 `5f9a6b08…`)
- Runner: `scripts/demo/observe_generate_review_enforce.sh` (sha256 `c71986db…`)
- Compiler: `scripts/policy/compile_policy.py` (sha256 `d2f6e853…`)
- Policy doc: `docs/POLICY_WORKFLOW.md`
- Sprint 9 demo runner: `scripts/demo/run_openhands_guard_demo.sh`
- Sprint 9 hand-rolled YAML: `policy/examples/openhands_action_server.yaml`
- Guard source: `guard/usernotify_exec_guard.c` (sha256 `842a687b…`, unchanged from Sprint 8)
- Guard binary: `bin/usernotify_exec_guard` (sha256 `1af638ca…`, unchanged from Sprint 8)
- Prior audit (Sprint 9 pass 2): `proofs/AUDIT_20260501_sprint9_independent_review_orchestrator_pass2.md`
- Sprint 9 cleanup memo: `proofs/SPRINT9_POST_AUDIT_CLEANUP_20260501.md`
- Audit history index: `proofs/AUDIT_HISTORY_INDEX_20260501.md`
