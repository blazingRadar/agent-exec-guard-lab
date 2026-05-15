# Sprint 9 — Orchestrator Independent Audit (Pass 2, with disagreement notes)

Date: 2026-05-01
Auditor: orchestrator (solo, second pass).
Posture: adversarial review of the Sprint 9 productization sprint, with live re-derivation; second pass after noticing a prior consolidated audit summary already exists at `AUDIT_20260501_sprint9_independent_review_orchestrator.md`.
Source of record: live commands; my own pass-1 draft (which missed three findings the prior consolidated summary caught) reconciled here.

---

## Post-Cleanup Addendum

This audit memo records the Sprint 9 findings as they existed before the post-audit cleanup. The findings below are preserved for traceability; their closure is recorded in `proofs/SPRINT9_POST_AUDIT_CLEANUP_20260501.md`.

Closure state after cleanup commit `664c4ad`:

| Finding | Current status |
| --- | --- |
| F-9-A hardcoded local path | Closed for prepared checkout: demo runner and Sprint 8 replay now derive repo root dynamically; public self-serve bootstrap still not claimed |
| F-9-B no container cleanup | Closed: runner uses an EXIT trap and preserved cleanup stdout/stderr |
| F-9-C README stale | Closed: README states Sprint 9 guided demo and post-audit cleanup passed |
| F-9-D missing aggregate pass row | Closed: passing cleanup run records `pass=14 fail=0` |
| F-9-F no recorded video/asciinema | Still open; outreach artifact, not Sprint 9 proof blocker |
| Public clone-and-run package | Still open; needs bootstrap docs/environment setup before claim is allowed |

The passing post-cleanup run is `proofs/sprint9_runs/sprint9-demo-20260501T040010Z`.

---

## Why a Pass-2 Memo Exists

When I went to write my Sprint 9 audit, I discovered a consolidated summary already at the canonical path. Reading it, it caught three findings my draft missed:

1. **Hardcoded local-machine paths** in the demo runner and DEMO.md — the prior summary correctly rates this **HIGH** because it invalidates any "clone and run one command" claim. My draft rated it LOW (cosmetic). The prior summary is right.
2. **Manual container cleanup** — the demo runner doesn't enforce post-run container cleanup. I missed this entirely.
3. **README status stale** — README stated Sprint 9 was "in progress" while the proof memo says PASS. I marked README as out of scope; it should have been verified.
4. **Missing aggregate `pass=N fail=0` row** in the demo summary — the runner records individual PASS lines but no aggregate footer like other replay harnesses. I overlooked this.

This pass-2 memo:
- Keeps the prior consolidated summary in place as the canonical Sprint 9 audit trail entry
- Records my own pass-1 gaps so the audit chain captures the correction
- Reconciles where the prior summary and my pass-1 draft disagreed (HIGH vs LOW on hardcoded paths) — I now agree with the prior summary's HIGH rating
- Adds independently verified pass-1 evidence the prior summary didn't fully cite

This is the same self-correction discipline pattern this lab applied to Sprint 5 (orchestrator follow-up review after the first round), Sprint 7 (idempotency defect retroactively fixed for both Sprint 7 and Sprint 8), and Sprint 8 (orchestrator audit added after the agent-driven audits hit token limits). The trail captures the self-correction.

---

## Verdict

**Sprint 9 substantively delivers as a guided/prepared-lab demo. It is not honest as a "clone and run on a fresh machine" demo claim.**

The prior summary's framing ("review-ready as a guided prepared-lab demo; not yet honest as a public self-serve 'clone and run one command' demo") is exactly right.

The honest one-line summary:

> "Sprint 9 packages the Sprint 8 frontier-model OpenHands guard proof into a one-command runner that works on the operator's local development machine: the YAML→JSON compiler with comprehensive fail-closed validation, the wrapper that orchestrates compile + 4 negative tests + the nested Sprint 8 path + secret scan, and the docs/DEMO.md page all landed and reproduce. At the time of this historical audit, the demo was not yet portable. The runner has since been updated to derive the repository root dynamically, while the prepared-lab dependency on Docker, pinned OpenHands source, and Python dependencies remains. Guard source and binary are unchanged from Sprint 8. The remaining outreach gap is portability + a recorded artifact."

---

## Findings (reconciled across both audits)

### F-9-A (HIGH) — Demo runner is local-machine shaped

The prior summary caught this. I confirm:

- `scripts/demo/run_openhands_guard_demo.sh:4` hardcoded the repository root at the time of this historical audit; current scripts derive the root dynamically.
- `docs/DEMO.md` example uses `--env-file .env.local` (a local env-file path)
- The demo runner assumes `external/OpenHands-1.6.0/` is already cloned at the pinned commit
- The demo runner assumes `.venv-sprint7/` Python venv exists with OpenHands deps

Implication: a reviewer who clones the public repo and runs `./scripts/demo/run_openhands_guard_demo.sh` on a fresh machine fails immediately. The "one-command demo" claim is true on the operator's machine and false elsewhere.

The prior summary rates this HIGH and calls for cleanup. I now agree HIGH (my pass-1 draft rated it LOW under "demo-portability nuance" — that was wrong; portability is the load-bearing property of a productized demo).

**Fix:** replace `ROOT` with `$(cd "$(dirname "$0")/../.." && pwd)`, replace DEMO.md's `--env-file` example with a generic instruction, add preflight checks (Docker accessible, OpenHands source present at pinned commit, Python deps available), and either bundle the venv setup into the runner or clearly document the prerequisite steps.

### F-9-B (MEDIUM) — Runner does not enforce post-run container cleanup

The prior summary caught this. I confirm by reading the demo runner: there is no `docker rm -f` after the OpenHands run completes. The Sprint 8 harness it invokes has a *pre*-run cleanup (`sg docker -c "docker rm -f '$CONTAINER_NAME'"` at line 19) but no *post*-run cleanup. So a successful demo leaves the container alive, requiring manual cleanup.

The user's "Sprint 9 cleanup memo" mentions cleaning containers manually after audit. Worth automating in the runner.

**Fix:** add `trap 'sg docker -c "docker rm -f $CONTAINER_NAME" >/dev/null 2>&1 || true' EXIT` near the top of the runner, or wrap the demo invocation in `try/finally`-style bash to guarantee cleanup on success and failure.

### F-9-C (MEDIUM) — README status stale

The prior summary caught this. I did not verify README.md myself in pass 1.

**Fix:** update README.md to reflect Sprint 9 PASS status with a link to `docs/DEMO.md` and the pinned OpenHands SHAs.

### F-9-D (LOW) — Demo summary lacks aggregate `pass=N fail=0` row

The prior summary caught this. I confirm by re-reading the demo summary file: it has 10 individual PASS lines but no aggregate footer like the Sprint 2/4/5/6/7/8 replay harnesses produce. The proof memo cites `pass=10 fail=0` but the runner itself doesn't emit that string.

**Fix:** add `printf 'pass=%s fail=%s\n' "$pass_count" "$fail_count" | tee -a "$SUMMARY"` at the end of the runner, matching the Sprint 8 pattern.

### F-9-E (LOW, my pass-1 finding worth keeping) — `--check-exists` is opt-in, not default

This was my pass-1 F1. The compiler has comprehensive validation but the file-existence check is optional. Defensible because the demo policy includes container paths that don't resolve on the host. The proof memo at line 117 names this honestly. Worth keeping in the carry-forward as a Sprint 10+ item if production-shape policies need stricter compile-time checks (perhaps via `--check-exists-in-container CONTAINER_IMAGE`).

### F-9-F (MEDIUM, not in Sprint 9 scope) — No recorded asciinema/video for outreach

This was my pass-1 F3. The prior summary doesn't name it. It's not a Sprint 9 deliverable gap (the gate didn't ask for video) but it's the remaining outreach gap. Belongs in a Sprint 10 / outreach prerequisite list, not in a Sprint 9 finding list.

### F-9-G (carry-forward) — F4 CONTINUE TOCTOU still deferred

Sprint 9 carries it forward honestly. Out of scope per gate.

---

## What Both Audits Agree On (Verified Clean)

- Pre-registration discipline holds: gate `2eed7e9` precedes proof `98125d9` by ~8 minutes in git timeline
- Guard source SHA `842a687b...` and binary SHA `1af638ca...` unchanged from Sprint 8
- YAML → JSON compiler with comprehensive fail-closed validation (top-level type, policy_id non-empty string, allowed_executables non-empty list, absolute paths only, no NUL, no duplicates, optional --check-exists)
- Compiler negative tests preserved with stderr showing fail-closed messages for each violation class
- Nested Sprint 8 frontier-model run produces `pass=11 fail=0` with real OpenAI gpt-5.2, real BLOCK on renamed `/usr/bin/rm`, structured trajectory assertion at `exit_code=126` with "Operation not permitted"
- Outer Sprint 9 demo records 10 PASS records (env_file, policy_compile, 4 compiler negative tests, openai_api_key_present, openhands_guard_demo, openhands_summary_present, secret_scan)
- API key hygiene: env-var sourced only, secret_scan PASS over run dir, no `sk-`/`sk-proj-` patterns in committed artifacts
- Carry-forward Open Items table present with full enumeration (F4 + non-CmdRunAction + FileRead/Write + IPython/Browse + Web UI + production image + production sandbox)
- `docs/DEMO.md` includes explicit "Non-Claims" section and matches the Sprint 9 proof memo's "Claims Still Not Allowed" enumeration
- `/tmp` not used for retained artifacts (gate item 13)

---

## Sprint 10 Punch List (combined)

Portability + outreach + demo-recording. In order:

1. **Replace hardcoded `ROOT` in demo runner** with self-locating path (`$(cd "$(dirname "$0")/../.." && pwd)`). F-9-A.
2. **Update DEMO.md `--env-file` example** to a generic path. F-9-A.
3. **Add preflight checks** to demo runner: Docker accessible, OpenHands source at pinned commit, Python venv present. F-9-A.
4. **Add post-run container cleanup** via trap. F-9-B.
5. **Sync README.md** to reflect Sprint 9 PASS state. F-9-C.
6. **Add aggregate pass=N fail=0 footer** to demo summary. F-9-D.
7. **Record asciinema** of the one-command demo for outreach. F-9-F.
8. **Pin OpenHands runtime image digest** in DEMO.md (currently references mutable `:1.6.0-nikolaik` tag).
9. **(Optional)** add `--check-exists-in-container` mode to the compiler. F-9-E.

After items 1-7, the demo claim becomes portable: any reviewer with Docker + an OpenAI API key + a clone of the public repo can `./scripts/demo/run_openhands_guard_demo.sh --env-file ./.env.local` and reproduce the proof.

F4 (CONTINUE TOCTOU) and non-CmdRunAction coverage remain the architectural items beyond demo readiness.

---

## Pass-1 Self-Correction Note

For audit-trail completeness, here's what my pass-1 draft got wrong:

| pass-1 rating | Correct rating | Why |
|---|---|---|
| Hardcoded paths: LOW (cosmetic) | HIGH | Invalidates "clone and run on fresh machine" claim |
| README: out of scope | MEDIUM in scope | Repo's user-facing surface drift is part of productization discipline |
| Container cleanup: not surfaced | MEDIUM | Productization discipline includes resource hygiene |
| Aggregate pass row: not surfaced | LOW | Consistency with rest of replay harness pattern matters for trustability |

The prior consolidated summary surfaced all four. My pass-1 missed them because I:
- Anchored on "the gate's items 1-13 are all PASS" without checking whether the *output shape* matched the rest of the lab's pattern
- Treated portability as a "demo nuance" instead of a productization deliverable
- Skipped reading README.md because the gate's deliverables list didn't name it

Lessons for future audits:
- When auditing a productization sprint, *portability is the load-bearing property*. The gate item "one-command demo runner" implies "runs anywhere," not "runs on the operator's machine."
- Compare the new sprint's output shape (summary file format, runner exit conventions) to the prior sprints' patterns. Drift is a finding.
- Always read README.md for status drift even if the gate doesn't name it.

---

## Files

- This audit (pass 2): `proofs/AUDIT_20260501_sprint9_independent_review_orchestrator_pass2.md`
- Prior consolidated summary: `proofs/AUDIT_20260501_sprint9_independent_review_orchestrator.md`
- Sprint 9 proof memo: `proofs/SPRINT9_PRODUCTIZED_DEMO_PROOF_20260501.md`
- Sprint 9 gate: `proofs/SPRINT9_GATE_20260501.md`
- Sprint 9 command log: `proofs/SPRINT9_COMMAND_LOG_20260501.md`
- Sprint 9 final run: `proofs/sprint9_runs/sprint9-demo-20260501T025441Z/`
- Demo runner: `scripts/demo/run_openhands_guard_demo.sh`
- Compiler: `scripts/policy/compile_policy.py`
- YAML policy: `policy/examples/openhands_action_server.yaml`
- Docs: `docs/DEMO.md`
- Source: `guard/usernotify_exec_guard.c` (sha256 `842a687b...`, unchanged from Sprint 8)
- Binary: `bin/usernotify_exec_guard` (sha256 `1af638ca...`, unchanged from Sprint 8)
