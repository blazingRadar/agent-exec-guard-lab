# Sprint 6B Command Log

Date: 2026-05-01

## Pre-Registration

The Sprint 6B gate was committed and pushed before implementation:

```text
c4392ae Pre-register Sprint 6B OpenHands command path gate
```

Gate file:

```text
proofs/SPRINT6B_GATE_20260501.md
```

## Source Inspection

OpenHands source was inspected locally from the pinned tag:

```bash
git clone --depth 1 --branch 1.6.0 --filter=blob:none \
  https://github.com/OpenHands/OpenHands.git external/OpenHands-1.6.0
git -C external/OpenHands-1.6.0 rev-parse HEAD
```

Observed commit:

```text
c5e0de8ecd85cef10e7808d57e9f939f3770ab9d
```

`external/` is ignored and not committed. The source commit is retained in run artifacts.

## Preserved Exploratory Runs

The following failed or partial runs were preserved instead of overwritten:

| Run | What it showed |
| --- | --- |
| `sprint6b-inspect-20260501T003923Z` | Runtime source/image inspection |
| `sprint6b-action-server-20260501T004101Z` | Runtime image did not provide importable `openhands` module by itself |
| `sprint6b-action-server-src-20260501T004123Z` | Mounted source with system Python lacked `httpx` and runtime deps |
| `sprint6b-action-server-mamba-20260501T004222Z` | Micromamba path reached but policy needed startup executables |
| `sprint6b-action-server-mamba-20260501T004255Z` | Additional startup helper policy tuning needed |
| `sprint6b-action-server-mamba-20260501T004330Z` | Root startup path did not yield a listening HTTP server |
| `sprint6b-action-server-mamba-20260501T004443Z` | New-user path attempted unsupported user setup |
| `sprint6b-action-server-daemon-20260501T004715Z` | Manual daemon-user action-server path succeeded |
| `sprint6b-action-server-20260501T004907Z` | Harness behavior succeeded but log capture was incomplete |
| `sprint6b-action-server-20260501T004956Z` | Final harness pass |

## Final Sprint 6B Replay

Command:

```bash
./scripts/integration/replay_sprint6b_action_server.sh
```

Result:

```text
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z
```

## Regression Replay

Command:

```bash
./scripts/replay_sprint2_identity.sh &&
./scripts/replay_sprint4_audit_integrity.sh &&
./scripts/integration/replay_sprint5_docker_guard.sh &&
./scripts/integration/replay_sprint6_openhands_runtime.sh
```

Results:

```text
Sprint 2: pass=12 fail=0
Sprint 4: pass=22 fail=0
Sprint 5: pass=11 fail=0
Sprint 6A: pass=13 fail=0
```

Run roots:

```text
proofs/sprint2_runs/sprint2-20260501T005021Z
proofs/sprint4_runs/sprint4-20260501T005022Z
proofs/sprint5_runs/sprint5-docker-20260501T005022Z
proofs/sprint6_runs/sprint6-openhands-runtime-20260501T005024Z
```

## Hashes

```text
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
ccfa471b1e2576913f0751138ac41d35a65aeefd746f3b6734ff2bac0d942393  policy/integration/openhands_action_server.allow.json
91d26f02acdbb769b2050eabe597fa128346bf353f52c4f1428459f69e498850  scripts/integration/replay_sprint6b_action_server.sh
dd30a713eda6af691c6a58879f8710a5fe0e3c102f7308d35fc37936d2a12134  proofs/SPRINT6B_GATE_20260501.md
```

## Cleanup Note

No retained host `/tmp` artifact was intentionally created by the Sprint 6B harness. The OpenHands server writes temporary state inside the Docker container, which is removed when the container is cleaned up.
