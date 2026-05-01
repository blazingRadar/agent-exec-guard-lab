# Sprint 5 Command Log

Date: 2026-04-30
Lab: `/home/blazingradar/agent-exec-guard-lab`

## Docker Access

Direct Docker access failed because the current shell did not include the `docker` group. `/etc/group` showed `blazingradar` is a docker-group member, and `sg docker -c 'docker ps'` worked. Sprint 5 Docker commands used `sg docker -c`.

## Target Probes

Pinned OpenHands release and manifests were checked:

```bash
gh repo view OpenHands/OpenHands
gh api repos/OpenHands/OpenHands/commits/main
sg docker -c "docker manifest inspect docker.openhands.dev/openhands/openhands:1.6.0"
sg docker -c "docker manifest inspect ghcr.io/openhands/runtime:1.6.0-nikolaik"
sg docker -c "docker buildx imagetools inspect docker.openhands.dev/openhands/openhands:1.6.0"
sg docker -c "docker manifest inspect --verbose ghcr.io/openhands/runtime:1.6.0-nikolaik"
```

Raw outputs were preserved under:

```text
proofs/sprint5_provenance/
```

Recorded target facts:

```text
OpenHands release: 1.6.0
app manifest digest: sha256:5c0dc26f467bf8e47a6e76308edb7a30af4084b17e23a3460b5467008b12111b
runtime amd64 digest: sha256:4959cef8059841fa5bf05fb1368d9ce5735d0ba94b2a3ceee335285e26529452
runtime amd64 compressed layer total observed by manifest: 2279980239 bytes
```

## Replay Commands

Sprint 5 Docker proof:

```bash
./scripts/integration/replay_sprint5_docker_guard.sh
```

Latest clean result:

```text
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T002321Z
pass=11 fail=0
```

Sprint 2 and Sprint 4 regression gates were then run sequentially:

```bash
./scripts/replay_sprint2_identity.sh
./scripts/replay_sprint4_audit_integrity.sh
```

Clean results:

```text
Sprint 2: pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260430T235805Z

Sprint 4: pass=22 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260430T235809Z
```

## Hashes

```text
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
5ec1cb09b2994f12306186949e175ad7d9c7d843eddd1f36d7c139b8c05cef86  scripts/integration/replay_sprint5_docker_guard.sh
7ccb1ceae281a50d0e50a6f7cd777c66adf863b6adbe1c1ede280254e8a2f8e6  policy/integration/docker_python_slim.allow.json
1f861067fae3a758c761b903d7458a5d8e7d40b79064d6cb07f5e0fd9f04d391  proofs/SPRINT5_GATE_20260430.md
```

## Notes

No retained `/tmp` artifacts were used for Sprint 5. A transient manual Docker probe was removed after the replay harness was tightened to run under Docker's default seccomp profile.
