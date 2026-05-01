# Local Proof Plan

Date: 2026-04-30

## Standard

Before any public demo, the local proof must be boring, repeatable, and falsifiable.

No tweet, README, HN post, OpenHands discussion, or public repo should ship until this plan passes locally.

## Phase 0: Environment Check

Confirm:

- Docker is installed
- Docker daemon is running
- host kernel supports seccomp
- host supports seccomp user notification if that path is used
- OpenHands can run locally or a raw Docker proof can run without OpenHands

Commands to verify later:

```bash
docker version
docker info
grep CONFIG_SECCOMP= /boot/config-$(uname -r)
grep CONFIG_SECCOMP_USER_NOTIF= /boot/config-$(uname -r)
```

## Phase 1: Raw Docker Baseline

Goal: prove the baseline behavior without any agent complexity.

Test cases:

- allowed: `git --version`
- allowed: `python3 --version`
- blocked candidate: `/bin/rm`
- blocked candidate: `curl ... | sh`
- blocked candidate: `python3 -c 'import subprocess; subprocess.run(...)'`

Expected baseline:

- Docker default profile allows normal process execution.
- Destructive commands may fail only because of filesystem state or permissions, not because `execve` is policy-blocked.

## Phase 2: Minimal Guard Proof

Goal: prove the guard changes behavior.

Expected guarded result:

- allowed commands still run
- denied executable paths are blocked
- denied attempts produce an audit record
- denial is deterministic across repeated runs

Audit log minimum:

```json
{
  "decision": "BLOCK",
  "reason": "blocked_executable",
  "exe": "/bin/rm",
  "argv": ["rm", "-rf", "/workspace"],
  "policy": "policy.strict.json"
}
```

## Phase 3: OpenHands Baseline

Goal: prove OpenHands can run locally and execute shell commands in its Docker sandbox.

Do not start with a security claim. Start with a capability claim:

> OpenHands can execute commands in its sandbox as designed.

Capture:

- OpenHands launch command
- sandbox/container IDs
- command executed by agent or controlled action
- proof that the command ran inside the sandbox

## Phase 4: OpenHands Guarded Run

Goal: inject the guard into the OpenHands sandbox path.

Success criteria:

- OpenHands still starts
- allowed dev commands still work
- blocked command fails at the runtime policy boundary
- audit record is created
- failure is clear enough for a 90-second video

## Phase 5: Reproducibility

Repeat from clean state:

- raw Docker baseline
- raw Docker guarded
- OpenHands baseline
- OpenHands guarded

Store results under `proofs/YYYYMMDD-run-id/`.

## Publication Gate

Only publish after:

- local proof passes twice
- artifacts are saved
- README is scoped honestly
- IP boundary is preserved
- threat model is written
- claims are reviewed for overstatement

If any phase fails, preserve the failure and decide whether the result is still useful.
