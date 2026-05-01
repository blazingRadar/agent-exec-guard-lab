# Sprint 10 Policy Workflow Proof

Date: 2026-05-01

Status: PASS

Gate commit: `6d91c21 Pre-register Sprint 10 policy workflow gate`

Final workflow run:

`proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z`

Generated-policy enforce run:

`proofs/sprint9_runs/sprint9-demo-20260501T080016Z`

Nested OpenHands run:

`proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z`

## Carry-Forward Open Items

| Item | Sprint 10 status |
| --- | --- |
| Public self-serve clone-and-run package | Still open |
| Recorded outreach video/asciinema | Still open |
| F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred and disclosed |
| Non-`CmdRunAction` paths | Out of scope |
| Full OpenHands web UI | Out of scope |
| Production-grade sandbox claim | Not allowed |

## What Changed

Sprint 10 added the product workflow layer:

- `scripts/policy/generate_policy_from_audit.py`
- `scripts/demo/observe_generate_review_enforce.sh`
- `docs/POLICY_WORKFLOW.md`

The guard source and binary were not changed.

## Workflow

Input observed guard log:

`proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined`

Generated YAML:

`proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.yaml`

Blocked-record summary:

`proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/blocked_records.json`

Compiled JSON:

`proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z/generated/openhands_observed.allow.json`

## Final Replay Result

Sprint 10 workflow summary:

```text
PASS env_file loaded env file path without persisting contents
PASS observe_log .../runtime_container_logs.combined
PASS generate_policy generated reviewable YAML from observed guard log
PASS compile_generated_policy generated YAML compiled to guard JSON
PASS generated_policy_assertions generated policy allows cat, excludes observed blocked rm
PASS enforce_generated_policy guided demo passed under generated policy
PASS enforce_summary .../demo_summary.txt
PASS secret_scan no API key pattern found in Sprint 10 artifacts
pass=8 fail=0
```

Policy generation summary:

```json
{
  "policy_id": "sprint10_observed_openhands_policy_v1",
  "allowed_executables": 16,
  "blocked_records": 10,
  "total_exec_decisions": 130
}
```

Generated-policy assertions:

```json
{
  "allowed_count": 16,
  "blocked_count": 10,
  "cat_allowed": true,
  "rm_allowed": false,
  "copied_rm_block_observed": true
}
```

Generated-policy enforce run:

```text
pass=14 fail=0
```

Nested OpenHands enforce run:

```text
pass=11 fail=0
```

## Preserved Failed Run

The first Sprint 10 run is preserved:

`proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z`

Result:

```text
pass=4 fail=1
```

Cause:

The generated-policy assertion expected a blocked record with `realpath=/usr/bin/rm`. The actual audit log correctly recorded the copied executable as `raw_exe="./python3"` with a workspace realpath. The assertion was wrong; the guard/audit behavior was correct. The assertion was tightened to check for the observed copied-`rm` block shape.

## Hashes

```text
842a687bb25a6abd7bb94c9da3ce1ccf28362a1e3964e36bae39a62278b8035a  guard/usernotify_exec_guard.c
1af638cab58de5ae8c4bb698a34332453a0cab2ef9ca5de1411f85718b3a7a97  bin/usernotify_exec_guard
5f9a6b08ce38e8fcbe24facfbbe9b49f1e2bece2b90ff058ace03d0af80860df  scripts/policy/generate_policy_from_audit.py
c71986db31d354a98cddc1c4d63068631e0ffbf09f640760937991d15f6f36d5  scripts/demo/observe_generate_review_enforce.sh
d2f6e85386eb4deacaa544348bdd20ad3370dd4a69d719c464c002293d1549c4  scripts/policy/compile_policy.py
```

## Claim Now Allowed

Sprint 10 adds an observe/generate/review/enforce workflow: real guard audit logs from the OpenHands demo are converted into reviewable YAML policy, observed BLOCK records are preserved separately, that YAML compiles to guard JSON, and the guided OpenHands demo reruns successfully under the generated policy while preserving the copied-`rm` block assertion.

## Claims Still Not Allowed

- Automatic approval without human review.
- Public self-serve clone-and-run packaging.
- Full OpenHands web UI coverage.
- Production-grade sandbox security.
- Complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure.
- fd-stable execution.
- Read/write/network isolation.
- Browser, Jupyter, MCP, `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, or non-`CmdRunAction` coverage.
