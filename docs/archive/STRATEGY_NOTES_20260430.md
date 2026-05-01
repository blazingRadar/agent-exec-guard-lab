# Strategy Notes: Agent Exec Guard

Date: 2026-04-30

## Core Thesis

The strongest public demo is a narrow, tangible runtime enforcement proof for AI coding agents:

> OpenHands-style coding agents can run inside Docker sandboxes, but Docker's default compatibility-oriented seccomp profile is broader than the task-scoped execution policy an autonomous agent should have. A drop-in runtime guard can block off-policy process execution below the model and emit an audit trail.

This should be framed as a hardening layer, not as a claim that OpenHands or Docker is broken.

## Why This Is Worth Testing

The demo has a concrete, visible behavior:

- without guard: a command executes
- with guard: the same command is blocked before process launch
- audit output explains the block

That is easier to understand than a broad governance lab and more shareable than a research packet.

## Primary Target

OpenHands is the first target to validate because:

- it is public and widely visible
- it uses Docker sandboxing for agent execution
- it has an obvious command-execution surface
- the integration can be no-fork if the guard can be injected through Docker/security options

The first proof should be raw Docker. OpenHands comes after raw Docker passes.

## Public Claim To Use If Validated

> I built a drop-in seccomp/user-notify execution guard for OpenHands-style coding agents. It blocks off-policy `execve` calls inside the Docker sandbox and emits an audit trail, without changing the agent itself.

## Claims To Avoid

Do not claim:

- OpenHands is vulnerable
- Docker sandboxing is broken
- this prevents all malicious agent behavior
- this is production-ready security
- this is the full Boundr system
- this proves kernel expertise as the core identity

Use:

- Docker default seccomp is broad by design
- autonomous agent workloads have narrower expected command surfaces
- runtime enforcement below the model is useful
- this is a minimal working guard
- the deeper governance system is private

## Public Deliverable Shape

Potential public repo:

```text
agent-exec-guard/
  README.md
  seccomp/
    agent-exec-guard.profile.json
  policy/
    policy.allow-dev.json
    policy.strict.json
  guard/
    minimal_notify_handler.c or .rs
  demos/
    openhands/
      docker-compose.yml
      run-without-guard.sh
      run-with-guard.sh
      prompts.md
    raw-docker/
      demo.sh
  attack_cases/
    allowed_git_status.sh
    blocked_rm_workspace.sh
    blocked_curl_pipe_sh.sh
    blocked_python_subprocess.sh
  docs/
    threat_model.md
    ip_boundary.md
    openhands_integration.md
```

This lab can evolve into that public shape only after local proof passes.

## Notoriety Package

If the proof validates, the public package should include:

1. A 90-second video:
   - default sandbox permits target command
   - guarded sandbox blocks the same command
   - audit JSON appears
2. A concise README:
   - "A drop-in execution guard for AI coding agents running in Docker sandboxes"
3. One technical post:
   - "Docker's default seccomp profile is built for compatibility. Autonomous coding agents need task-scoped execution policy."

Avoid drama. Optimize for serious engineers sharing a reproducible finding.
