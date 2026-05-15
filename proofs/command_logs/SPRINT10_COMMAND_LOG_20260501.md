# Sprint 10 Command Log

Date: 2026-05-01

Scope: observe/generate/review/enforce policy workflow.

## Pre-Registration

```bash
git add proofs/SPRINT10_GATE_20260501.md
git commit -m "Pre-register Sprint 10 policy workflow gate"
git push origin main
```

Result:

```text
6d91c21 Pre-register Sprint 10 policy workflow gate
```

## Implementation Checks

```bash
chmod +x scripts/policy/generate_policy_from_audit.py scripts/demo/observe_generate_review_enforce.sh
bash -n scripts/demo/observe_generate_review_enforce.sh
python3 -m py_compile scripts/policy/generate_policy_from_audit.py scripts/policy/compile_policy.py
```

## Smoke Test

```bash
LOG=proofs/sprint9_runs/sprint9-demo-20260501T040010Z/openhands_runs/sprint8-frontier-agent-20260501T040010Z/runtime_container_logs.combined
scripts/policy/generate_policy_from_audit.py "$LOG" /tmp/sprint10_observed.yaml --include-blocked-summary /tmp/sprint10_blocked.json
scripts/policy/compile_policy.py /tmp/sprint10_observed.yaml /tmp/sprint10_observed.json
rm -f /tmp/sprint10_observed.yaml /tmp/sprint10_observed.json /tmp/sprint10_blocked.json
```

The `/tmp` smoke outputs were removed immediately and were not retained as proof artifacts.

## Preserved Failed Run

```bash
./scripts/demo/observe_generate_review_enforce.sh --env-file .env.local
```

Run:

```text
proofs/sprint10_runs/sprint10-policy-workflow-20260501T075952Z
```

Result:

```text
pass=4 fail=1
```

Cause:

Incorrect assertion expected blocked copied-`rm` to appear as `realpath=/usr/bin/rm`; actual audit record correctly shows `raw_exe="./python3"` with a workspace realpath.

## Passing Run

```bash
./scripts/demo/observe_generate_review_enforce.sh --env-file .env.local
```

Run:

```text
proofs/sprint10_runs/sprint10-policy-workflow-20260501T080016Z
```

Result:

```text
pass=8 fail=0
```

Generated-policy enforce run:

```text
proofs/sprint9_runs/sprint9-demo-20260501T080016Z
pass=14 fail=0
```

Nested OpenHands run:

```text
proofs/sprint9_runs/sprint9-demo-20260501T080016Z/openhands_runs/sprint8-frontier-agent-20260501T080016Z
pass=11 fail=0
```

## Cleanup Check

```bash
sg docker -c "docker ps -a --format '{{.Names}} {{.Status}}' | grep '20260501T080016Z\\|sprint10-policy-workflow' || true"
```

Result: no matching runtime containers remained.
