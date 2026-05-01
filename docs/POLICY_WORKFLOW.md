# Policy Workflow

Sprint 10 adds a guided observe/generate/review/enforce loop.

## Workflow

1. Start from a successful guarded OpenHands run.
2. Parse the guard audit stream.
3. Generate reviewable YAML from observed `ALLOW` executable identities.
4. Preserve observed `BLOCK` records separately.
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

## Non-Claims

This workflow does not claim:

- automatic approval without human review;
- public self-serve bootstrap;
- production sandbox security;
- complete `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU closure;
- non-`CmdRunAction` coverage;
- read/write/network isolation.

## Review Boundary

The generated YAML intentionally includes only observed `ALLOW` executable identities. Observed `BLOCK` records are written to a separate JSON summary so a reviewer can see what was excluded.
