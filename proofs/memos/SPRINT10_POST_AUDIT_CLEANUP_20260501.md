# Sprint 10 Post-Audit Cleanup

Date: 2026-05-01

Status: PASS

## Audit Findings Addressed

| Finding | Cleanup action |
| --- | --- |
| F-10-A BLOCK/ALLOW overlap not reconciled | Generator now excludes any realpath that appears in both `ALLOW` and `BLOCK`, and records `blocked_overlap_excluded` in metadata |
| F-10-B / F-10-F identity evidence discarded | Generator now emits `observed_identity_evidence` with observed raw exe, sha256, dev, ino, first/last line, and observation count |
| F-10-C input provenance implicit | Generator now supports `--trusted-root` and `--require-policy-id`; Sprint 10 runner uses both. `--require-policy-id` rejects unexpected `policy_id` values when present; it does not require every record to carry one. |
| F-10-D review field not enforced | Docs now state the runner performs automated shape checks and does not enforce human approval |
| F-10-F partial preflight | Sprint 10 runner now checks generator, compiler, and guided demo runner before continuing |
| F-10-G hardcoded pass count | Sprint 10 runner now accepts any `pass=N fail=0` enforce summary |
| Latest demo pointer could select no-key failed run | Sprint 10 runner now auto-discovers the latest actual OpenHands guard log instead of trusting `latest_demo.txt` |
| Documentation overclaim | `docs/POLICY_WORKFLOW.md` now names audit-log trust boundary and non-claims |
| README launch framing buried | README top section now leads with the OpenHands execve gap, threat model, expected BLOCK output, comparison framing, and guided-demo boundary |

## Remaining Boundaries

- Public self-serve clone-and-run packaging remains open.
- Recorded outreach video/asciinema remains open.
- Audit logs are not signed or tamper-proof.
- Human approval is recommended but not enforced by the runner.
- Guard runtime still consumes path allowlists and rebinds identity at policy load time.
- F4 and non-`CmdRunAction` coverage remain out of scope.

## Validation Results

Local crafted-input probes:

1. ALLOW and BLOCK overlap for the same realpath must exclude that realpath from generated `allowed_executables`.
2. Mismatched `policy_id` must fail when `--require-policy-id` is set.
3. Audit path outside `--trusted-root` must fail.

Result:

- `proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132858Z/probe_summary.txt`
- `pass=3 fail=0`

Preserved failed probe wrapper:

- `proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132835Z/`
- The generator output was valid, but the inline Python assertion used the wrong shape for `observed_identity_evidence` and the shell wrapper did not stop on the non-zero assertion. This is preserved with `FAILURE_NOTE.md`; the corrected rerun used `set -euo pipefail`.

Full policy workflow rerun:

- `proofs/sprint10_runs/sprint10-policy-workflow-20260501T132905Z/workflow_summary.txt`
- `pass=11 fail=0`

Generated-policy enforce run:

- `proofs/sprint9_runs/sprint9-demo-20260501T132905Z/demo_summary.txt`
- `pass=14 fail=0`

Verified:

- generated YAML compiles;
- generated YAML includes identity evidence;
- generated YAML excludes copied/renamed `rm`;
- generated-policy enforce run passes with `fail=0`;
- no API key pattern appears in Sprint 10 artifacts.

## Claim After Cleanup

Sprint 10 now supports this narrower product-workflow claim:

> A reviewed guard audit log can be converted into a YAML allowlist operator that preserves observed executable identity evidence, excludes any executable identity also seen in a BLOCK record, compiles to the guard JSON format, and can rerun the OpenHands guided demo successfully under the generated policy.

This does not make the repository public self-serve. It does not enforce human approval. It does not sign audit logs. It does not close F4.
