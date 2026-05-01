# Sprint 5 Gate: Docker/OpenHands Integration Reality Check

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`
Posture: integration proof, not F4 architecture work.

## Goal

Prove whether the current seccomp user-notify + Landlock execution guard can be used in a realistic containerized AI coding-agent workflow, with F4 explicitly disclosed.

## Carry-Forward Open Items

| ID | Item | Sprint 5 status |
|---|---|---|
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred. Sprint 5 does not attempt `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. It must be named in all claims. |
| Docker access | Local user must be able to use Docker without interactive sudo | Gate dependency. If Docker socket remains inaccessible, Sprint 5 must stop with a blocker memo rather than fake integration. |
| OpenHands target | Target version/SHA must be pinned before any integration claim | Required before any OpenHands-specific claim. |

## Acceptance Criteria

Sprint 5 can claim integration only if all of these pass:

1. Docker or the selected OpenHands runtime is actually runnable from this machine.
2. The target OpenHands version/SHA or image digest is recorded.
3. The guard runs in the command-execution path, not just next to it.
4. At least three cases are replayed and saved:
   - allowed policy executable runs
   - copied/renamed non-policy executable is blocked
   - child stderr JSON forgery is captured as child output, not supervisor decision
5. Audit JSON remains parseable end-to-end.
6. Sprint 2 replay still passes.
7. Sprint 4 replay still passes.
8. F4 is explicitly carried forward in the Sprint 5 memo.

## Non-Goals

- No `SECCOMP_IOCTL_NOTIF_ADDFD + execveat` implementation.
- No ptrace rewrite.
- No upstream OpenHands PR.
- No production-grade sandbox claim.
- No claim that OpenHands is vulnerable unless reproduced against a pinned target.
- No Docker/OpenHands claim if Docker cannot be run locally.

## Current First Probe

`docker version` reports Docker Engine client version `29.1.3`, but access to the Docker daemon fails:

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

This is a gate blocker until Docker permissions are fixed or an alternate OpenHands runtime can be run without Docker.

## Docker Access Update

The current shell does not include the `docker` group in `id`, but `/etc/group` lists `blazingradar` as a member of `docker`.

Non-interactive Docker access works with:

```bash
sg docker -c 'docker ps'
```

Sprint 5 Docker commands must therefore use `sg docker -c ...` unless the login session is refreshed.

## Pinned OpenHands Target

Pinned release:

- Repository: `OpenHands/OpenHands`
- Release: `1.6.0`
- Release date: `2026-03-30T16:01:39Z`
- Release URL: `https://github.com/OpenHands/OpenHands/releases/tag/1.6.0`
- App image manifest: `docker.openhands.dev/openhands/openhands:1.6.0`
- Runtime image manifest: `ghcr.io/openhands/runtime:1.6.0-nikolaik`

Current `main` at probe time:

- SHA: `72ac92f4aa6e2fe7229403d569882c016ec19756`
- Date: `2026-04-30T23:03:43Z`

Sprint 5 will target release `1.6.0` first, not floating `main`.
