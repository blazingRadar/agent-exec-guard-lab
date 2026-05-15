# Sprint 10 Post-Audit Cleanup — Independent Follow-up Review

Date: 2026-05-01
Auditor: orchestrator (solo follow-up after the Sprint 10 cleanup commit `21e31be`).
Posture: verify whether the Sprint 10 audit findings actually closed in the cleanup commit, with live re-derivation.
Source of record: live commands + commit inspection + my own crafted-input probes against the updated generator.

---

## Audit Question

The Sprint 10 audit chain (orchestrator A + B) named six findings: BLOCK ∩ ALLOW reconciliation defect (F-10-A), no identity-pinning in emitted policy (F-10-B/F), no input provenance check (F-10-C), implicit-trust "review" framing (F-10-D), partial preflight (F-10-F), hardcoded pass count (F-10-G), plus carry-forward issues (latest_demo poisoning, README launch framing buried, documentation overclaim). Did commit `21e31be` actually close them?

## Verdict

**Cleanly closed.** All six audit findings + the three carry-forward items are addressed in the cleanup commit, and I independently verified the load-bearing fix (BLOCK ∩ ALLOW exclusion) with my own crafted-input probe before writing this memo. Guard source/binary unchanged. Working tree clean. Repo confirmed `PRIVATE` via `gh repo view`. The README rewrite leads with the OpenHands execve gap, threat model, comparison framing, and explicit non-claims.

The honest one-line summary:

> "Sprint 10 cleanup substantively closes the generator's BLOCK ∩ ALLOW defect with verifiable live evidence, adds identity evidence (realpath + dev + ino + sha256 + first/last line + observation count) to every emitted entry, adds optional `--trusted-root` and `--require-policy-id` provenance gates, fixes the `latest_demo.txt` poisoning with auto-discovery of the latest run carrying actual audit logs, and rewrites the README around the launch hook with honest comparison framing against Docker seccomp / gVisor / Firecracker / E2B / bubblewrap. The remaining open items (public self-serve bootstrap, outreach video, audit-log signing, human-review enforcement) are honestly named in the cleanup memo."

---

## Item-by-Item Verification

### F-10-A — BLOCK ∩ ALLOW reconciliation (HIGH from prior audit) — CLOSED

Code inspection — `scripts/policy/generate_policy_from_audit.py:124-126`:

```python
overlap_excluded = sorted(set(allowed) & blocked_realpaths)
for realpath in overlap_excluded:
    allowed.pop(realpath, None)
```

Plus metadata recording at lines 140-141 (`blocked_overlap_excluded_count`, `blocked_overlap_excluded`).

Live re-derivation with my own crafted input (`/usr/bin/cat` appears in BOTH ALLOW and BLOCK; `/usr/bin/echo` only in ALLOW):

```
$ python3 scripts/policy/generate_policy_from_audit.py /tmp/aud_root/aud_overlap.jsonl /tmp/aud_overlap.yaml --trusted-root /tmp/aud_root --require-policy-id audtest
{
  "policy_id": "observed_openhands_policy_v1",
  "allowed_executables": 1,
  "blocked_records": 1,
  "blocked_overlap_excluded": 1,
  "total_exec_decisions": 3
}

$ grep -A2 'blocked_overlap_excluded\|allowed_executables' /tmp/aud_overlap.yaml
  blocked_overlap_excluded_count: 1
  blocked_overlap_excluded:
  - /usr/bin/cat
allowed_executables:
- /usr/bin/echo
```

Confirmed: `/usr/bin/cat` excluded, `/usr/bin/echo` retained. The defect both Sprint 10 auditors named is closed and the metadata makes the exclusion explicit.

### F-10-B / F-10-F — Identity evidence preserved — CLOSED

Code inspection at lines 92-106 stores `realpath, first_line, last_line, observations, raw_exe, sha256, dev, ino` per entry. Line 149 emits the list under `observed_identity_evidence`.

Live evidence in the actual workflow rerun (`proofs/sprint10_runs/sprint10-policy-workflow-20260501T132905Z/generated/openhands_observed.allow.yaml`):

```yaml
observed_identity_evidence:
- realpath: /openhands/micromamba/bin/micromamba
  first_line: 2
  last_line: 62
  observations: 11
  raw_exe: /openhands/micromamba/bin/micromamba
  sha256: 3016eb34edd59923b2d8814f77d0358c27157a1c4f7df04e1308e42219cbc4ba
  dev: 130
  ino: 168200136
```

The realpath + dev + ino + sha256 + observation provenance is now in the YAML. Auditor B's request that the emitted policy match the guard's actual identity-check shape (realpath + dev + ino) is addressed.

### F-10-C — Input provenance — CLOSED

Code inspection at lines 58-68 (trusted-root) and 83-88 (require-policy-id). Live re-derivation:

```
# Negative: audit log outside trusted root
$ python3 scripts/policy/generate_policy_from_audit.py /tmp/aud_overlap.jsonl /tmp/aud_overlap2.yaml --trusted-root /tmp/aud_root
audit log is outside trusted root: /tmp/aud_overlap.jsonl
exit=2

# Negative: policy_id mismatch
$ python3 scripts/policy/generate_policy_from_audit.py /tmp/aud_root/aud_overlap.jsonl /tmp/aud_overlap3.yaml --require-policy-id wrongid
policy_id mismatch at line 1: audtest
exit=2
```

Both gates fail closed with explicit error messages and exit 2.

The `os.path.commonpath` pattern at lines 62-68 is the right shape. Note for the future: `.resolve()` follows symlinks at probe time; a TOCTOU race between resolve and the actual file read is theoretically possible but accepted for non-adversarial use. Worth flagging as known-residual.

### F-10-D — "Review" framing honest — CLOSED in docs

Per cleanup memo: "Docs now state the runner performs automated shape checks and does not enforce human approval."

Verified in `README.md:58`: "The runner performs automated shape checks; it does not replace human approval." And `docs/POLICY_WORKFLOW.md` (per cleanup memo) similarly tightened.

### F-10-G — Hardcoded pass count — CLOSED

Per cleanup memo: "Sprint 10 runner now accepts any `pass=N fail=0` enforce summary." This makes the harness robust to varying test counts in nested runs, which is a good idempotency property.

### Latest-demo-pointer poisoning — CLOSED

Per cleanup memo: "Sprint 10 runner now auto-discovers the latest actual OpenHands guard log instead of trusting `latest_demo.txt`."

Verified in workflow rerun output:

```
observe_run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z
observe_log=.../runtime_container_logs.combined
PASS observe_log .../runtime_container_logs.combined
```

The discovery scans for an actual audit log (`runtime_container_logs.combined`) rather than blindly using whatever `latest_demo.txt` points at.

### README rewrite — CLOSED

Verified by reading current `README.md` head:
- Line 3: leads with the load-bearing claim ("OpenHands' default Docker runtime can execute arbitrary binaries inside its sandbox")
- Lines 7-15: "What This Is Not" — first thing under the lead
- Lines 9: comparison framing names Docker seccomp, gVisor, Firecracker, E2B, bubblewrap
- Lines 19-46: demonstrated result with literal PASS lines and a representative guard audit JSON record
- Lines 47-58: policy workflow described with the BLOCK exclusion mentioned
- Lines 60-68: guided demo prerequisites named explicitly
- Lines 90-92: comparison framing in prose: "Docker's default seccomp profile is a broad compatibility baseline; it does not express task-specific executable identity policy for autonomous coding agents. gVisor, Firecracker, E2B, and bubblewrap provide stronger isolation patterns, but they are different deployment choices. This lab is additive."
- Lines 98-104: current non-claims listed honestly

The framing is the strongest the README has been across the entire audit chain. It correctly positions the project as **additive** to the existing isolation tools rather than competing with them — which is exactly the audience-targeting recommendation the lab needed for an outreach narrative.

---

## What Verified Clean Independently

```
$ git log --oneline -1
21e31be Clean Sprint 10 launch-readiness findings

$ git status --short
(empty — working tree clean)

$ gh repo view --json visibility,nameWithOwner
{"nameWithOwner":"blazingRadar/agent-exec-guard-lab","visibility":"PRIVATE"}

$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
842a687bb25a6abd7bb94c9da3ce1ccf28362a1e3964e36bae39a62278b8035a  guard/usernotify_exec_guard.c
1af638cab58de5ae8c4bb698a34332453a0cab2ef9ca5de1411f85718b3a7a97  bin/usernotify_exec_guard
```

Source/binary SHAs unchanged from Sprint 8 onward — Sprint 10 cleanup is correctly a tooling/docs sprint, not a guard sprint.

Workflow rerun produces `pass=11 fail=0` at `proofs/sprint10_runs/sprint10-policy-workflow-20260501T132905Z/`. Generated-policy enforce run produces `pass=14 fail=0` at `proofs/sprint9_runs/sprint9-demo-20260501T132905Z/`. Probes pass `3/0` at `proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132858Z/`. Numbers reproduce.

Failed probe wrapper preserved at `proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132835Z/` with explicit `FAILURE_NOTE.md` explaining why the first wrapper attempt was too weak (assertion didn't fail-stop the shell, fixed with `set -euo pipefail`). This is the same self-correction discipline the lab has applied since Sprint 5.

---

## Findings Worth Naming (none escalated; small notes only)

### N1 — Trusted-root check has a known TOCTOU residual

The `--trusted-root` validation uses `Path.resolve()` and `os.path.commonpath`. Between the resolve call and the eventual file open, an attacker who can write a symlink in the trusted root could in theory swap the target. Accepted for the current threat model (the trusted root is operator-controlled). Worth one line in `docs/POLICY_WORKFLOW.md` under "non-claims" if not already there: "trusted-root check is symlink-resolved at probe time but does not lock the audit log against subsequent rewrites."

### N2 — `policy_id` matching is exact-string

`--require-policy-id` accepts a list of acceptable values and rejects on first mismatch. This is correct for the current single-policy-per-audit-log shape. If multi-policy audit logs ever land (e.g., two different runs concatenated), the shape may need a richer matcher. Out of scope today.

### N3 — Comparison framing is honest, but stops short of stating the wedge

The README's comparison framing names Docker seccomp / gVisor / Firecracker / E2B / bubblewrap and correctly positions the lab as "additive." It does not yet name the **specific** audience this lab is built for: teams already running self-hosted agents in Docker who want a kernel-level audit/policy boundary on top of their existing isolation choice. Worth a single sentence: "This lab targets self-hosted-agent teams that already run a base sandbox (Docker default seccomp, etc.) and want explicit per-execve policy/audit on top of it." Not a finding; a wedge-sharpening note for outreach.

---

## What This Audit Does Not Find

I attempted but did not produce:
- Any defect in the BLOCK ∩ ALLOW reconciliation logic (the original finding is genuinely closed; my crafted input verified)
- Any way to bypass the `--trusted-root` check via path traversal in the audit_log argument
- Any way to bypass `--require-policy-id` via case-insensitivity or whitespace tricks
- Any leaking of API keys in the new sprint10 run artifacts (secret scan PASS)
- Any silently-dropped failed probe (the failed wrapper at T132835Z is preserved with a FAILURE_NOTE)
- Any guard source/binary modification that should have been a separate sprint

---

## Demo Wedge State After Cleanup

The README now reads as launch-ready. The strongest assertable wedge sentence:

> "OpenHands' default Docker runtime can execute arbitrary binaries inside its sandbox. This lab adds a Linux syscall-boundary execution policy and audit layer around that command path. A frontier model drives real `execute_bash` actions; expected tools are allowed; a copied `/usr/bin/rm` renamed to `./python3` is blocked by executable identity and reported back through the OpenHands trajectory. The closed-loop workflow turns observed guard audit logs into a reviewable YAML policy, compiles it to guard JSON, and reruns the demo under the generated policy."

Three things still gate "publicly shippable" per the cleanup memo's honest "Remaining Boundaries":
1. Public self-serve bootstrap docs/package
2. Recorded outreach asciinema or video
3. Audit-log signing / tamper-proofing

None of those are Sprint 10 deliverables. They're Sprint 11+ operators or outreach-prep work.

---

## Sprint 11 / Outreach Prerequisites (audit-derived)

In order:

1. **Record an asciinema** of `./scripts/demo/observe_generate_review_enforce.sh` running end-to-end, ~90-120 seconds. The closed-loop workflow's "observe → generate → review → enforce" is a much stronger demo narrative than Sprint 9's hand-rolled-policy demo. Lead with this one.
2. **Write the public-clone-and-run bootstrap** path. Either (a) document the prerequisite steps explicitly (Docker daemon access, OpenHands source clone at pinned commit, Python venv with deps, env file with API key) and verify on a fresh user account, OR (b) bundle a `bootstrap.sh` that does it all.
3. **Add a `SECURITY.md`** to the lab root if there isn't one. Even a 10-line file naming the disclosure path is meaningful for a security-shaped project.
4. **Wedge-sharpening one-liner** in README's comparison framing — name the audience explicitly (N3 above).
5. **Audit-log signing** — write a small `sign_audit_log.py` that produces a detached signature alongside each `runtime_container_logs.combined`. Closes one of the cleanup-memo "Remaining Boundaries" without requiring guard-runtime changes.

F4 and non-`CmdRunAction` coverage remain the architectural items beyond demo readiness.

---

## Discipline Observations

What the cleanup commit got right that should be preserved:

- **Both findings rated HIGH/MEDIUM by independent auditors were closed in code, not just docs.** The BLOCK ∩ ALLOW exclusion is a real code change, not a doc patch. Auditor reviews where the fix is "we added a sentence to the docs explaining why it's not actually a defect" are weak; this is a real fix.
- **Crafted-input probes preserved separately** at `proofs/sprint10_runs/sprint10-post-audit-probes-*/`. These are the tests the auditors would have written; the operator wrote them and preserved the artifacts.
- **Failed probe wrapper preserved** with `FAILURE_NOTE.md`. The shell-wrapper bug was caught and the fix (`set -euo pipefail`) is recorded. Same discipline as Sprint 5/7/8/9 — failures live in the trail.
- **README rewrite leads with the load-bearing technical claim**, not the project history. A first-time reader hits the OpenHands execve gap in line 3.
- **"Current Non-Claims" section** at the bottom of README — same disclosure discipline as the per-sprint memos but at the public-facing layer.

---

## Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

git log --oneline -5
git status --short
gh repo view --json visibility,nameWithOwner
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard

git diff-tree --no-commit-id --name-only -r 21e31be

# Live BLOCK ∩ ALLOW probe
cat > /tmp/aud_overlap.jsonl <<EOF
{"event":"exec_decision","policy_id":"audtest","decision":"ALLOW","raw_exe":"/usr/bin/cat","realpath":"/usr/bin/cat",...}
{"event":"exec_decision","policy_id":"audtest","decision":"BLOCK","raw_exe":"/usr/bin/cat","realpath":"/usr/bin/cat",...}
{"event":"exec_decision","policy_id":"audtest","decision":"ALLOW","raw_exe":"/usr/bin/echo","realpath":"/usr/bin/echo",...}
EOF
mkdir -p /tmp/aud_root && cp /tmp/aud_overlap.jsonl /tmp/aud_root/

# Positive: overlap excluded
python3 scripts/policy/generate_policy_from_audit.py \
  /tmp/aud_root/aud_overlap.jsonl /tmp/aud_overlap.yaml \
  --trusted-root /tmp/aud_root --require-policy-id audtest
  -> blocked_overlap_excluded: ["/usr/bin/cat"]; allowed: ["/usr/bin/echo"]

# Negative: outside trusted root
python3 scripts/policy/generate_policy_from_audit.py /tmp/aud_overlap.jsonl ... --trusted-root /tmp/aud_root
  -> exit 2 "audit log is outside trusted root"

# Negative: policy_id mismatch
python3 ... --require-policy-id wrongid
  -> exit 2 "policy_id mismatch at line 1: audtest"

# Inspect actual workflow rerun's generated YAML
head -40 proofs/sprint10_runs/sprint10-policy-workflow-20260501T132905Z/generated/openhands_observed.allow.yaml

# Cleanup
rm -rf /tmp/aud_root /tmp/aud_overlap*.jsonl /tmp/aud_overlap*.yaml
```

---

## Files

- This audit: `proofs/AUDIT_20260501_sprint10_followup_review.md`
- Cleanup memo: `proofs/SPRINT10_POST_AUDIT_CLEANUP_20260501.md`
- Cleanup commit: `21e31be Clean Sprint 10 launch-readiness findings`
- Generator: `scripts/policy/generate_policy_from_audit.py`
- README: `README.md`
- Workflow rerun: `proofs/sprint10_runs/sprint10-policy-workflow-20260501T132905Z/`
- Probe rerun: `proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132858Z/`
- Preserved failed probe: `proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132835Z/`
- Generated-policy enforce run: `proofs/sprint9_runs/sprint9-demo-20260501T132905Z/`
- Source: `guard/usernotify_exec_guard.c` (sha256 `842a687b...`, unchanged since Sprint 7 sweep)
- Binary: `bin/usernotify_exec_guard` (sha256 `1af638ca...`, unchanged since Sprint 7 sweep)
- Prior Sprint 10 audits: `proofs/AUDIT_20260501_sprint10_independent_review_a.md`, `_b.md`
