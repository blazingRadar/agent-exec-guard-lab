# Policy Workflow

Sprint 10 adds a guided observe/generate/review/enforce loop.

## Workflow

1. Start from a successful guarded OpenHands run.
2. Parse the guard audit stream.
3. Generate reviewable YAML from observed `ALLOW` executable identities.
4. Preserve observed `BLOCK` records separately and exclude any realpath that appears in both `ALLOW` and `BLOCK`.
5. Compile YAML into the guard JSON format.
6. Rerun the guided OpenHands demo using the generated policy.

## Command

```bash
export OPENAI_API_KEY=...
./scripts/demo/observe_generate_review_enforce.sh
```

Optional:

```bash
./scripts/demo/observe_generate_review_enforce.sh \
  --observe-run-root proofs/sprint9_runs/<run>/openhands_runs/<openhands-run> \
  --env-file .env.local
```

## Product Claim

This is a prepared-lab policy workflow, not a public installer.

It proves that real guard audit logs can produce a reviewable YAML allowlist which compiles and can be used for a subsequent guided enforce run.

## Trust Boundary

The audit log is part of the trust boundary. The workflow is intended for logs produced by this guard in the local `proofs/` tree. The generator can enforce a trusted root and reject unexpected source `policy_id` values when present, but it does not require every record to carry a `policy_id` and it does not make arbitrary third-party JSON trustworthy.

The generated YAML includes an `observed_identity_evidence` section with the observed `sha256`, `dev`, `ino`, and line numbers for review. The guard still consumes only `allowed_executables`; runtime identity is rebound by the guard when the compiled policy is loaded.

## Non-Claims

This workflow does not claim:

- automatic approval without human review;
- signed or tamper-proof audit logs;
- public self-serve bootstrap;
- production sandbox security;
- complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure;
- non-`CmdRunAction` coverage;
- read/write/network isolation.

## Review Boundary

The generated YAML includes observed `ALLOW` executable realpaths except any realpath also seen in a `BLOCK` record. Observed `BLOCK` records are written to a separate JSON summary so a reviewer can see what was excluded.

The current runner performs automated shape checks. It does not enforce a human approval prompt before the generated policy is used.
