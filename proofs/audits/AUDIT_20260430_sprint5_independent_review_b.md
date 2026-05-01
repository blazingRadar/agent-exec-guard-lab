# Sprint 5 — Independent Audit Review (Auditor B)

Date: 2026-04-30
Auditor: Auditor B (independent adversarial pass on Sprint 5 self-claim `SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`).
Posture: re-derive provenance, re-run the Docker replay live, probe the load-bearing seccomp / Landlock / PID-namespace questions for "guard inside Docker default profile," check carry-forward discipline against the Sprint 3/4 audit recommendation, separate "guard runs in a container" from "agent-in-container is supervised by guard," and re-test Sprint 1/2/4 invariants live inside the container.
Source of record: live commands run on this machine; SHAs re-derived; F1/F2/F5/F6/Landlock/seccomp re-tested inside the container under Docker's default seccomp profile.

A parallel Auditor A ran the same brief independently. I did not coordinate. Both auditors' replay runs are visible in `proofs/sprint5_runs/`, `proofs/sprint2_runs/`, and `proofs/sprint4_runs/` from late `2026-04-30T17:0xZ` PDT.

---

## 1. Audit Question

Does Sprint 5 prove that the existing seccomp user-notify + Landlock execution guard runs inside a Docker container under Docker's default seccomp profile, with Sprint 1/2/4 invariants intact, F4 explicitly carried forward, OpenHands 1.6.0 pinned but not pulled, and the gate honestly pre-registered?

## 2. Verdict

**Sprint 5's runnable claim is real and reproducible. The guard works inside `python:3.12-slim` under Docker's default builtin seccomp profile, without `--security-opt seccomp=unconfined`. `seccomp(SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER)` and the three `landlock_*` syscalls are live-traced reaching the kernel inside the container. F1, F2, F5, and F6 still close inside the container. Sprint 2 (12) and Sprint 4 (22) regression replays still pass. F4 is explicitly carried forward. OpenHands 1.6.0 is pinned in both gate and proof. The headline "Docker container proof" is accurate but only in interpretation (a) — guard-runs-in-a-container — not interpretation (b) — agent-in-container-supervised-by-guard.**

Two real discipline notes (neither rises to "block Sprint 5"):

- **Pre-registration is materially preserved by file mtimes, but git-history alone does not prove it.** `SPRINT5_GATE_20260430.md`, `SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`, the command log, the replay harness, and all replay run artifacts were added in a *single* commit `e972a70`. Filesystem mtimes show the gate was finalized at 16:55 PDT, the first failed replay attempt at 16:56:02 PDT, and the final passing replay at 17:00:55 PDT — so the gate did land before the replay artifacts on disk by ~1 minute. But a stricter pre-registration discipline would commit the gate first (creating an immutable git timestamp) and then commit the proof in a follow-up. Sprint 6 should split this.
- **The Sprint 5 Carry-Forward Open Items table only lists three rows** (F4, OpenHands runtime, production-grade sandboxing). Sprint 4's own memo had a fuller table covering F1-F8 + sweep items A1/A2/A3/A4/B5/B6. Sprint 5 should have inherited and re-stamped those rows with "regression-verified inside container, see Sprint 4 replay (22 cases pass)." It does not. It is mitigated by the fact that the 22-case Sprint 4 replay is rerun and reported, but the table itself is thin.

The honest one-line summary of Sprint 5's actual state:

> "A locally built seccomp user-notify + Landlock guard binary, mounted via bind-mount into a `python:3.12-slim` container running under Docker's default builtin seccomp profile, can allow an approved container executable, block a copied non-policy executable before it runs, and demote a child-written forged-JSON exec_decision to a `child_stderr` envelope. Sprint 2 identity replay (12 cases) and Sprint 4 audit-integrity replay (22 cases) both pass against the same Sprint-4-sweep binary. The OpenHands 1.6.0 release and runtime image digests are pinned and recorded but neither image was pulled or exercised this sprint."

Recommend: **Sprint 5 is kept**. Sprint 6 must do (a) gate-then-proof commit split and (b) actually pull and exercise an OpenHands command-execution path or the pinned runtime image.

---

## 3. Discipline Check — Was the Gate Pre-Registered? Was Carry-Forward Open Items Present?

### 3.1 Pre-registration

The git history shows a single commit `e972a70` ("Sprint 5 Docker container integration proof", `Thu Apr 30 17:01:43 2026 -0700`) added all of:

- `proofs/SPRINT5_GATE_20260430.md`
- `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`
- `proofs/SPRINT5_COMMAND_LOG_20260430.md`
- `scripts/integration/replay_sprint5_docker_guard.sh`
- `policy/integration/docker_python_slim.allow.json`
- All replay run dirs under `proofs/sprint5_runs/`, `proofs/sprint2_runs/sprint2-202604{30T235747Z,30T235805Z}`, `proofs/sprint4_runs/sprint4-202604{30T235748Z,30T235809Z}`

```
$ git log --diff-filter=A --follow -- proofs/SPRINT5_GATE_20260430.md
commit e972a70af96938e82fee39b9acb0ce7eff2b47ef
Date:   Thu Apr 30 17:01:43 2026 -0700
$ git log --diff-filter=A --follow -- proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
commit e972a70af96938e82fee39b9acb0ce7eff2b47ef
Date:   Thu Apr 30 17:01:43 2026 -0700
```

So git alone does not prove the gate landed before the proof memo. They are co-staged.

Filesystem mtimes do, however, preserve a useful fact:

| Artifact | mtime |
|---|---|
| `proofs/SPRINT5_GATE_20260430.md` | `Apr 30 16:55` |
| `scripts/integration/replay_sprint5_docker_guard.sh` | `Apr 30 17:00` |
| First failed replay run dir (`sprint5-docker-20260430T235602Z`) | UTC ≅ 16:56:02 PDT |
| Final passing replay run dir (`sprint5-docker-20260501T000055Z`) | UTC ≅ 17:00:55 PDT |
| `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` | `Apr 30 17:01` |
| `proofs/SPRINT5_COMMAND_LOG_20260430.md` | `Apr 30 17:01` |

Reading the gate body: section "Current First Probe" records a Docker socket permission denial; section "Docker Access Update" records the `sg docker -c` workaround; section "Pinned OpenHands Target" records OpenHands `1.6.0` and runtime image digests with `Current main at probe time` of `2026-04-30T23:03:43Z` (= 16:03:43 PDT). So the gate was *authored* iteratively starting around 16:03 PDT and *finalized* around 16:55 PDT, then the harness was run, then the proof memo was written and the bundle was committed at 17:01 PDT.

This is **materially honest** pre-registration — the gate was on disk before any replay run was started — but it is **not** what a strict observer would call "pre-registered" because there is no immutable git timestamp distinguishing the gate from the proof. A future Sprint should commit the gate alone, then commit the proof+log+replay artifacts in a follow-up commit. This is a one-off discipline gap, not a fatal one.

### 3.2 Carry-Forward Open Items

Both gate and proof memo open with a `## Carry-Forward Open Items` header (gate at line 11; proof at line 7). Good — adopts the Sprint 3 audit's recommendation that Sprint 4 first followed.

But the *content* of the table is thin. The proof memo's table has three rows:

| ID | Item | Sprint 5 status |
|---|---|---|
| F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred and still disclosed. |
| OpenHands full runtime | Prove against the pinned OpenHands command runtime image | Not yet claimed. |
| Production-grade sandboxing | Complete sandbox claim | Not allowed. |

Sprint 4's own carry-forward table covered F1-F8 plus sweep items A1, A2, A3, A4, B5, B6. The Sprint 5 memo dropped them all. They are *not* unimportant — they are exactly the open items a reader of Sprint 5 needs to see "still closed inside a container" or "still deferred." Mitigation: the 22-case Sprint 4 replay is rerun and reported as `pass=22 fail=0`, which exercises every row of A1/A2/A3/B6 + F1/F2/F3/F5/F6/F7/F8. So in spirit the regression is verified; in form, the table doesn't show it. Sprint 6 should re-stamp the full table.

---

## 4. What Verified Clean Independently

### 4.1 Re-derived hashes and line counts

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
            scripts/integration/replay_sprint5_docker_guard.sh \
            policy/integration/docker_python_slim.allow.json \
            proofs/SPRINT5_GATE_20260430.md \
            proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
edbed7ca0eaed27300893354b9066c370b4d6ff175310bd6cce00d547ac8ff07  scripts/integration/replay_sprint5_docker_guard.sh
7ccb1ceae281a50d0e50a6f7cd777c66adf863b6adbe1c1ede280254e8a2f8e6  policy/integration/docker_python_slim.allow.json
1f861067fae3a758c761b903d7458a5d8e7d40b79064d6cb07f5e0fd9f04d391  proofs/SPRINT5_GATE_20260430.md
4f498d767485029ae00445678b0194f73451d1ca8acc810070eb5067ec0e35ce  proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
$ wc -l guard/usernotify_exec_guard.c
1369 guard/usernotify_exec_guard.c
```

Source/binary/replay-script/policy SHAs match what the Sprint 5 command log (line 67-71) records.

**Source line-count delta vs the Sprint 4 audit (1258 lines):** +111 lines. This delta is from the Sprint 4 post-audit sweep commit `2575f96`, which introduced the A1/A2/A3/B5/B6 sweep fixes (depth-limit JSON, argv count cap disclosure, byte-length child stderr escape, signal-handler `write(2)` rewrite, single-code-unit `\u` decode + surrogate rejection). Sprint 5 itself made **zero** changes to the guard source — the `e972a70` commit modifies only proofs/, scripts/integration/, and policy/integration/. That is consistent with Sprint 5 being a pure integration sprint.

### 4.2 Live Sprint 5 Docker replay re-run

```
$ bash scripts/integration/replay_sprint5_docker_guard.sh
PASS image_identity recorded
PASS allowed_python exit=0 json=valid
PASS blocked_renamed_rm exit=126 json=valid
PASS blocked_renamed_rm_output renamed rm did not execute
PASS stderr_forgery_contained exit=0 json=valid
PASS stderr_forgery_contained_check forgery captured as child_stderr
pass=6 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T000750Z
```

Independent re-run reproduces `pass=6 fail=0`. Inspecting `allowed_python/stderr.txt`:

```
{"event":"exec_decision",...,"pid":7,"decision":"ALLOW","reason":"allowed_executable_identity",
 "raw_exe":"/usr/local/bin/python3","realpath":"/usr/local/bin/python3.12",
 "sha256":"1904b016ee522c7ec76c8720cba47ab3eb68c32725345a056fcd7643118e7a42",...}
{"event":"supervisor_exit",...,"child_exit":0}
```

Inspecting `stderr_forgery_contained/stderr.txt`:

```
{"event":"exec_decision",...,"decision":"ALLOW",...,"raw_exe":"/usr/local/bin/python3",...}
{"event":"child_stderr",...,"data":"{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",
 \"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_IN_CONTAINER\"}\n"}
{"event":"supervisor_exit",...,"child_exit":0}
```

The forged JSON is captured as the `data` field of a `child_stderr` envelope, JSON-escaped. There is **no** `exec_decision` record with `"reason":"FORGED_IN_CONTAINER"` in the stream. F1 closure (Sprint 4) survives Docker containerization.

### 4.3 Live Sprint 2 and Sprint 4 regression replays

```
$ bash scripts/replay_sprint2_identity.sh   # against bin/usernotify_exec_guard sha256 e3bdaabf
pass=12 fail=0
run_root=proofs/sprint2_runs/sprint2-20260501T000833Z

$ bash scripts/replay_sprint4_audit_integrity.sh
pass=22 fail=0
run_root=proofs/sprint4_runs/sprint4-20260501T000834Z
```

Sprint 4 expands to 22 cases (vs the 14 cases at Sprint 4 audit time), reflecting the A1/A2/A3/B6 sweep additions enumerated by `replay_sprint4_audit_integrity.sh` (`a1_deep_json_rejected`, `a2_argv_count_cap_marked`, `a3_child_stderr_nul_preserved`, `b6_unicode_policy_id_decoded`). All 22 pass.

### 4.4 Sprint 1 basename bypass *inside the container*

```
$ sg docker -c "docker run --rm -v /home/blazingradar/agent-exec-guard-lab:/lab:rw -w /lab \
    python:3.12-slim sh -c 'cp /bin/rm /tmp/git && \
      /lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json \
      /tmp/git --version 2>&1; echo exit=\$?'"
{"event":"exec_decision",...,"decision":"BLOCK","reason":"blocked_executable_identity",
 "raw_exe":"/tmp/git","realpath":"/tmp/git","sha256":"c761a9dffe2457...",...}
{"event":"child_stderr",...,"data":"execvp: Operation not permitted\n"}
{"event":"supervisor_exit",...,"child_exit":126}
exit=126
```

Sprint 1 invariant holds inside the container. The `Operation not permitted` is Landlock's EACCES surfaced via execvp (since the user-notify decision was BLOCK before exec, and the Landlock layer denies execute on non-policy paths).

### 4.5 F1 fd-guess inside the container

```
$ sg docker -c "docker run --rm -v ...:/lab:rw -w /lab python:3.12-slim sh -c \
    '/lab/bin/usernotify_exec_guard --policy ... /usr/local/bin/python3 -c \"
import os
for fd in range(3, 30):
    try: os.write(fd, b\\\"FORGE_FD_\\\"+str(fd).encode()+b\\\"\\n\\\")
    except OSError: pass\"'"
{"event":"exec_decision",...,"decision":"ALLOW",...}
{"event":"supervisor_exit",...,"child_exit":0}
```

No `FORGE_FD_*` strings appear in the audit stream. The supervisor's audit fd is unreachable to the child inside the container.

### 4.6 F2 SIGTERM inside the container

```
$ sg docker -c "docker run --rm -v ...:/lab:rw -w /lab python:3.12-slim sh -c \
    '/lab/bin/usernotify_exec_guard --policy ... /usr/local/bin/python3 -c \
     \"import os,signal; os.kill(os.getppid(), signal.SIGTERM)\"; echo exit=\$?'"
{"event":"exec_decision",...,"decision":"ALLOW",...}
{"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGTERM"}
exit=143
```

Signal handler emits the final record before `_exit(143)`. F2 closure holds inside the container.

### 4.7 F5 — `/proc/<child_pid>/exe` resolves in the **container's** PID namespace

The audit records above show `"pid":7` and `"pid":13` — these are **container-local** PIDs (not host PIDs). The supervisor reading `/proc/<child_pid>/exe` from inside the container uses the container's `/proc` mount, which views the container's PID namespace. The realpath fields (`/usr/local/bin/python3.12`, `/tmp/git`, `/lab/proofs/.../renamed_rm_python3`) are container-local resolved paths, confirming the proc mount used is the container's. F5 works correctly under the container PID namespace.

### 4.8 F6 — AF_ALG SHA256 inside the container

Every exec_decision record above carries a real `"sha256"` value (e.g. `1904b016ee52...` for `python3.12`). AF_ALG works inside the container without needing CAP_SYS_ADMIN or any special namespace privileges.

### 4.9 Landlock works inside Docker default seccomp profile

```
$ sg docker -c "docker run --rm -v ...:/lab:rw -w /lab python:3.12-slim sh -c \
    'apt-get update -qq && apt-get install -y -qq strace && \
     strace -ff -o /tmp/sx \
       -e trace=landlock_create_ruleset,landlock_add_rule,landlock_restrict_self,seccomp \
       /lab/bin/usernotify_exec_guard --policy ... /usr/local/bin/python3 --version 1>/dev/null 2>&1; \
     cat /tmp/sx.* | grep -E \"landlock|seccomp\"'"
seccomp(SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, {len=8, filter=...}) = 3
landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION) = 7
landlock_create_ruleset({handled_access_fs=LANDLOCK_ACCESS_FS_EXECUTE, handled_access_net=0}, 16, 0) = 3
landlock_add_rule(3, LANDLOCK_RULE_PATH_BENEATH, {allowed_access=LANDLOCK_ACCESS_FS_EXECUTE, parent_fd=4}, 0) = 0
... (six more landlock_add_rule)
landlock_restrict_self(3, 0) = 0
```

All four landlock syscalls and the seccomp `SECCOMP_SET_MODE_FILTER + SECCOMP_FILTER_FLAG_NEW_LISTENER` syscall succeed inside the container. The fd `3` returned by `seccomp()` is the user-notify listener fd that the supervisor then reads notifications from.

### 4.10 Container caps and seccomp posture confirmed

```
$ sg docker -c "docker run --rm python:3.12-slim sh -c \
    'cat /proc/self/status | grep -E \"^(CapEff|CapBnd|NoNewPrivs|Seccomp|Seccomp_filters)\"'"
CapEff:	00000000a80425fb
CapBnd:	00000000a80425fb
NoNewPrivs:	0
Seccomp:	2
Seccomp_filters:	1
```

`a80425fb` is Docker's default ambient cap mask (no `CAP_SYS_ADMIN`). `Seccomp:2` confirms Docker's default builtin seccomp profile is applied. `Seccomp_filters:1` (the engine's own filter) — and the supervisor adds its own listener filter on top, then `seccomp(...)` returns the listener fd. So the Sprint 5 claim "Docker's default seccomp profile" is accurate, *not* `seccomp=unconfined`, *not* `--privileged`, *not* `CAP_SYS_ADMIN`. This is the load-bearing claim of Sprint 5 and it is real.

---

## 5. Critical Findings

**None.** No new bypass class introduced by Sprint 5. The integration sprint touched no guard source code; the only artifacts are the bind-mount Docker harness + container policy + run records.

---

## 6. Container-Specific Findings (Sprint 5's New Surface)

### 6.1 "Docker container proof" means interpretation (a), not (b)

The brief asks: does the proof prove *(a)* "guard binary copied (here: bind-mounted) into a container, supervising an ordinary process inside the container," or *(b)* "an agent process running inside a container, with the guard wrapping the agent"?

The replay harness is unambiguous. Each case is a `docker run --rm -v <repo>:/lab:rw -w /lab python:3.12-slim` invoking the supervisor binary at `/lab/bin/usernotify_exec_guard` against an in-container target (`/usr/local/bin/python3 --version`, a bash script that `cp /bin/rm` then runs the copy, or a Python script that writes a forged exec_decision JSON to its own stderr). There is no agent. There is no OpenHands runtime. The forged-stderr case is a **stand-in** for a hypothetical agent attempting audit forgery — useful as a regression but not the same as exercising a real agent.

The proof memo correctly does *not* claim (b). It says: "No claim that this is integrated with OpenHands yet" and "No claim that the pinned OpenHands runtime image has been pulled or exercised." The headline "Docker container proof" is honest because it does not say "agent integration proof."

For OpenHands integration, only (b) is load-bearing. Sprint 6 must do (b).

### 6.2 Bind-mount is rebuildable from committed sources, but not "containerized"

There is **no `Dockerfile`** in the Sprint 5 commit. The harness uses `python:3.12-slim` from Docker Hub, bind-mounts the repo at `/lab`, and runs the host-built `bin/usernotify_exec_guard` directly. Image identity recorded in the run dir:

```
sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286
python@sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286
```

Strengths: the proof is reproducible exactly because the image and binary are both content-addressed, and the bind-mount approach avoids the ABI risks of a separately compiled in-container build.

Weaknesses: a future "ship the guard inside an image" step is not yet started. For OpenHands integration, the guard needs to be either (a) part of an OpenHands-derived image or (b) exposed via an init-container / sidecar. Sprint 6 work.

Caveat about base image userns: the `python:3.12-slim` container runs as **root** (uid 0) inside the container by default. This is the standard Docker default, but a future hardening step might run the guard as a non-root user inside the container (after the seccomp/landlock work is done, drop privileges before fork+exec).

### 6.3 Docker default profile permits `seccomp(SET_MODE_FILTER, NEW_LISTENER)` even without CAP_SYS_ADMIN

I directly probed:

```
$ sg docker -c "docker run --rm python:3.12-slim python3 -c '
import ctypes, ctypes.util, os, errno
libc = ctypes.CDLL(ctypes.util.find_library(\"c\"), use_errno=True)
SECCOMP_SET_MODE_FILTER = 1
SECCOMP_FILTER_FLAG_NEW_LISTENER = 1 << 3
rc = libc.syscall(317, SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, 0)
err = ctypes.get_errno(); print(\"rc\", rc, \"errno\", err, errno.errorcode.get(err, \"?\"))'"
rc -1 errno 14 EFAULT
```

`EFAULT` (rather than `EPERM` or `ENOSYS`) means the kernel actually entered the seccomp syscall and tried to dereference the NULL filter pointer. Docker's default builtin seccomp profile does not block the `seccomp` syscall on this engine. (Kernel: 6.17.0; Docker engine: 29.1.3.) This is a property of the current default profile and the kernel allowing user-notify without CAP_SYS_ADMIN; it is **not** guaranteed for older kernels (pre-5.9) or for distributions that ship a tighter custom profile. Sprint 5 should explicitly note this; the proof memo does not (it just says "default Docker seccomp profile" without qualifying which kernel/engine version).

### 6.4 PID namespace works correctly (no host-PID leak in audit)

The audit records show container-local PIDs (`"pid":7`, `"pid":13`). The supervisor's `/proc/<child_pid>/exe` lookup uses the container's `/proc`, which views the container PID namespace, so no host-PID leak. F5 closure holds.

### 6.5 Operator-overrides-guard-binary is out of threat model — confirmed

If the operator launches `docker run -v /home/operator/evil_guard:/lab/bin/usernotify_exec_guard ...`, the operator can replace the binary. This is out of the guard's threat model (the guard's threat model is the supervised child, not the operator) and was already disclosed in earlier sprints. The Sprint 5 memo does not need to re-disclose it because nothing in Sprint 5 changes the operator-trust boundary.

### 6.6 No namespace-exit class introduced

I did not attempt a namespace-escape probe. That is Docker's job, not the guard's. The guard does not call `setns`, `unshare`, or anything that would extend the container boundary.

### 6.7 cgroup CPU limits and signal-handler timing

Out of Sprint 5 scope; not tested. F2 signal-handler emits a fixed-string `write(2)` followed by `_exit`, which is a small constant-time path. cgroup CPU throttling could in theory delay the handler but would not change the audit record content.

---

## 7. F4 Deferral and OpenHands Handoff State

### 7.1 F4 disclosure

F4 (`SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU) is named in:

- `proofs/SPRINT5_GATE_20260430.md` line 9 (Goal), line 15 (Carry-Forward table), line 33 (Acceptance Criterion 8), line 37 (Non-Goals).
- `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` line 5 (Posture), line 11 (Carry-Forward table), line 95 ("No claim that F4 is fixed.").

Disclosure is preserved.

### 7.2 OpenHands 1.6.0 pinning

OpenHands 1.6.0 is recorded in three places:

- `proofs/SPRINT5_GATE_20260430.md` lines 66-82 (release URL, app image manifest reference, runtime image reference, current `main` SHA `72ac92f4...` at probe time).
- `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` lines 34-43 (release date `2026-03-30T16:01:39Z`, app manifest digest `sha256:5c0dc26f...`, runtime amd64 digest `sha256:4959cef8...`, runtime image size 2.28 GB).
- `proofs/SPRINT5_COMMAND_LOG_20260430.md` lines 26-30.

I confirmed the GitHub release tag exists:

```
$ gh api repos/OpenHands/OpenHands/releases/tags/1.6.0 | jq '.tag_name, .published_at'
"1.6.0"
"2026-03-30T16:01:39Z"
```

Pinning is real, not chat-only. Discipline is preserved.

The runtime image **was not pulled** this sprint. The proof memo says so explicitly ("about 2.28 GB compressed for amd64, so this sprint did not pull it as part of the first container proof"). The image manifest *digest* is recorded, which is sufficient for a future Sprint 6 to assert exact target identity.

### 7.3 The "child-written forged JSON captured as child_stderr" claim is a regression test, not a new finding

The Sprint 4 audit (audit B section 3.4 F1) verified that a child writing `{"event":"exec_decision","decision":"ALLOW","raw_exe":"/bin/rm","reason":"FORGED_S4"}` to its own stderr is captured as a JSON-escaped `child_stderr` envelope, *not* a parsed exec_decision. Sprint 5 reproduces the same property inside a Docker container with a different forged reason (`FORGED_IN_CONTAINER`). The mechanism is identical:

- Supervisor `audit_fd = fcntl(STDERR_FILENO, F_DUPFD_CLOEXEC, 3)` before fork.
- Child's stderr is `dup2`'d to a `pipe2` write end before execve.
- Supervisor reads the child stderr pipe and emits `child_stderr` records with `data` JSON-escaped via `json_escape`.

The container does not change any of this. So Sprint 5's `stderr_forgery_contained_check` is a **regression test that the F1 closure is not somehow broken by container namespacing or the bind-mount mechanism** — exactly what an integration sprint should verify, and exactly how it is framed.

---

## 8. Sprint 6 Prerequisites (audit-derived)

1. **Commit-split discipline**: Sprint 6 should commit (a) the gate alone first, then (b) replay artifacts + proof memo + command log in a follow-up. This makes pre-registration verifiable by git timestamps without requiring filesystem mtime archaeology.
2. **Carry-forward table fidelity**: Sprint 6's carry-forward table should re-stamp F1-F8 + A1/A2/A3/A4/B5/B6 with status, not just the new sprint-specific items (F4, OpenHands runtime, production-grade sandbox).
3. **Pull and exercise the OpenHands runtime image** (`ghcr.io/openhands/runtime:1.6.0-nikolaik`, digest `sha256:4959cef8...`). This is the (b) interpretation that Sprint 5 explicitly defers. The acceptance criterion is "the guard is in the agent's command-execution path and blocks a non-policy executable from a real agent attempt, with parseable audit output," not "OpenHands launches."
4. **Kernel/engine version disclosure**: the proof memo should record the host kernel (6.17.0) and Docker engine (29.1.3) used for the proof, because the "default seccomp profile permits seccomp(NEW_LISTENER) without CAP_SYS_ADMIN" property is engine-version-dependent.
5. **Optional: ship a Dockerfile** for the guard so an operator can `docker build` an image rather than bind-mounting the host binary. This decouples the guard's ABI from the host.
6. **F4 architectural close** remains the eventual blocker for any "production-grade sandbox" claim: prototype `SECCOMP_IOCTL_NOTIF_ADDFD + execveat` (Φ_B in Sprint 3 fix-path analysis).

---

## 9. Honest Claim That Should Replace the Sprint 5 Headline

The Sprint 5 self-claim under "Claim Now Allowed":

> "A local seccomp user-notify plus Landlock execution guard can run inside a Docker container under Docker's default seccomp profile, allow an approved container executable, block a copied non-policy executable before it runs, and preserve the Sprint 4 audit-forgery boundary by demoting child-written JSON to `child_stderr`."

**Current claim is accurate.** No tightening required.

Two minor tightenings would be welcome but are not required:

- Add "(host kernel 6.17.0, Docker engine 29.1.3, default builtin seccomp profile)" to scope the seccomp-default claim to a verified kernel/engine pair.
- Replace "preserve the Sprint 4 audit-forgery boundary" with "regression-verify the Sprint 4 audit-forgery boundary holds inside the container" to make explicit that Sprint 5 is *not* introducing a new boundary, only confirming the existing one survives containerization.

The "Claims Still Not Allowed" list correctly excludes OpenHands integration, runtime-image exercise, F4 fix, production-grade sandbox, and read/write/networking/non-execute syscall surfaces. Discipline is preserved.

---

## 10. Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

# Discipline check — was the gate pre-registered?
git log --oneline -20
git log --diff-filter=A --follow -- proofs/SPRINT5_GATE_20260430.md
git log --diff-filter=A --follow -- proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
git log --diff-filter=A --follow -- proofs/SPRINT5_COMMAND_LOG_20260430.md
git log --diff-filter=A --follow -- scripts/integration/replay_sprint5_docker_guard.sh
git show --stat e972a70 | head -80
ls -la proofs/SPRINT5_GATE_20260430.md proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md \
       proofs/SPRINT5_COMMAND_LOG_20260430.md scripts/integration/replay_sprint5_docker_guard.sh

# Re-derive provenance
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
          scripts/integration/replay_sprint5_docker_guard.sh \
          policy/integration/docker_python_slim.allow.json \
          proofs/SPRINT5_GATE_20260430.md proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
wc -l guard/usernotify_exec_guard.c
git show 2cf79f0:guard/usernotify_exec_guard.c | wc -l   # 1258 (initial)
git show 2575f96:guard/usernotify_exec_guard.c | wc -l   # 1369 (post Sprint 4 sweep)
git diff 2575f96..e972a70 -- guard/usernotify_exec_guard.c   # empty — Sprint 5 didn't touch the guard
git log --oneline --name-status -- guard/usernotify_exec_guard.c

# Docker access
id ; groups ; getent group docker
docker ps   # permission denied
sg docker -c 'docker ps'   # works
sg docker -c 'docker version' | grep -E 'Version|Engine'
sg docker -c "docker info --format '{{.SecurityOptions}}'"
  -> [name=apparmor name=seccomp,profile=builtin name=cgroupns]

# Live Sprint 5 Docker replay re-run
bash scripts/integration/replay_sprint5_docker_guard.sh
  -> pass=6 fail=0  run_root=proofs/sprint5_runs/sprint5-docker-20260501T000750Z

# Inspect captured audit JSON for the three Sprint 5 cases
cat proofs/sprint5_runs/sprint5-docker-20260501T000750Z/allowed_python/stderr.txt
cat proofs/sprint5_runs/sprint5-docker-20260501T000750Z/blocked_renamed_rm/stderr.txt
cat proofs/sprint5_runs/sprint5-docker-20260501T000750Z/stderr_forgery_contained/stderr.txt

# Sprint 1 basename bypass inside container
sg docker -c "docker run --rm -v /home/blazingradar/agent-exec-guard-lab:/lab:rw -w /lab \
    python:3.12-slim sh -c 'cp /bin/rm /tmp/git && \
      /lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json \
      /tmp/git --version 2>&1; echo exit=\$?'"
  -> BLOCK reason=blocked_executable_identity exit=126

# F1 fd-guess inside container
sg docker -c "docker run --rm -v ...:/lab:rw -w /lab python:3.12-slim sh -c \
    '/lab/bin/usernotify_exec_guard --policy ... /usr/local/bin/python3 -c \"
import os
for fd in range(3, 30):
    try: os.write(fd, b\\\"FORGE_FD_\\\"+str(fd).encode()+b\\\"\\n\\\")
    except OSError: pass\"'"
  -> no FORGE_FD_* in audit stream

# F2 SIGTERM inside container
sg docker -c "docker run --rm -v ...:/lab:rw -w /lab python:3.12-slim sh -c \
    '/lab/bin/usernotify_exec_guard --policy ... /usr/local/bin/python3 -c \
     \"import os,signal; os.kill(os.getppid(), signal.SIGTERM)\"; echo exit=\$?'"
  -> {"event":"supervisor_exit","reason":"killed_by_signal","signal":"SIGTERM"}; exit=143

# Probe whether seccomp(SET_MODE_FILTER, NEW_LISTENER) is reachable in default profile
sg docker -c "docker run --rm python:3.12-slim python3 -c '
import ctypes, ctypes.util, errno
libc = ctypes.CDLL(ctypes.util.find_library(\"c\"), use_errno=True)
rc = libc.syscall(317, 1, 1<<3, 0)
err = ctypes.get_errno(); print(\"rc\", rc, \"errno\", err, errno.errorcode.get(err, \"?\"))'"
  -> rc -1 errno 14 EFAULT  (kernel processed the syscall; not blocked by Docker default profile)

# Container caps and seccomp posture
sg docker -c "docker run --rm python:3.12-slim sh -c \
    'cat /proc/self/status | grep -E \"^(CapEff|CapBnd|NoNewPrivs|Seccomp|Seccomp_filters)\"'"
  -> CapEff:00000000a80425fb (no CAP_SYS_ADMIN); NoNewPrivs:0; Seccomp:2; Seccomp_filters:1

# strace seccomp + landlock_* live inside container
sg docker -c "docker run --rm -v ...:/lab:rw -w /lab python:3.12-slim sh -c \
    'apt-get update -qq && apt-get install -y -qq strace && \
     strace -ff -o /tmp/sx \
       -e trace=landlock_create_ruleset,landlock_add_rule,landlock_restrict_self,seccomp \
       /lab/bin/usernotify_exec_guard --policy ... /usr/local/bin/python3 --version 1>/dev/null 2>&1; \
     cat /tmp/sx.* | grep -E \"landlock|seccomp\"'"
  -> seccomp(SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, ...) = 3
     landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION) = 7
     landlock_create_ruleset({handled_access_fs=...EXECUTE...}, 16, 0) = 3
     landlock_add_rule(3, LANDLOCK_RULE_PATH_BENEATH, ...) = 0  (×7)
     landlock_restrict_self(3, 0) = 0

# Regression replays against Sprint 4 binary
bash scripts/replay_sprint2_identity.sh
  -> pass=12 fail=0  run_root=proofs/sprint2_runs/sprint2-20260501T000833Z
bash scripts/replay_sprint4_audit_integrity.sh
  -> pass=22 fail=0  run_root=proofs/sprint4_runs/sprint4-20260501T000834Z

# OpenHands 1.6.0 verification
gh repo view OpenHands/OpenHands | head
gh api repos/OpenHands/OpenHands/releases/tags/1.6.0 | head
  -> tag 1.6.0 exists; published_at 2026-03-30T16:01:39Z (matches gate)

# Carry-forward / disclosure scan
grep -nE 'OpenHands|1.6.0|Carry-Forward|F4|A1|A2|A3|A4|B5|B6|sweep' \
  proofs/SPRINT5_GATE_20260430.md proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md \
  proofs/SPRINT5_COMMAND_LOG_20260430.md
  -> F4 disclosed in 4 locations across gate+proof; OpenHands 1.6.0 in 3 docs;
     Sprint 5 carry-forward table only has 3 rows (F4, OpenHands runtime, production sandbox);
     A1/A2/A3/A4/B5/B6 not enumerated.

# /tmp cleanup check
ls /tmp/git_audit_b /tmp/python3_audit_b /tmp/spoof_s4.policy.json /tmp/eq.json
  -> none present (prior audit cleaned up)
```

No /tmp artifacts created by this audit on the host. Inside containers, every probe used `--rm` so container state is destroyed at exit. The new run dirs `proofs/sprint5_runs/sprint5-docker-20260501T000750Z/`, `proofs/sprint2_runs/sprint2-20260501T000833Z/`, `proofs/sprint4_runs/sprint4-20260501T000834Z/` are intentionally preserved on disk as part of the audit trail (matching Sprint 4 audit-B convention).

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint5_independent_review_b.md`
- Sprint 5 gate: `proofs/SPRINT5_GATE_20260430.md` (sha256 `1f861067...`)
- Sprint 5 proof memo: `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` (sha256 `4f498d76...`)
- Sprint 5 command log: `proofs/SPRINT5_COMMAND_LOG_20260430.md`
- Sprint 5 replay harness: `scripts/integration/replay_sprint5_docker_guard.sh` (sha256 `edbed7ca...`)
- Sprint 5 container policy: `policy/integration/docker_python_slim.allow.json` (sha256 `7ccb1cea...`)
- Source: `guard/usernotify_exec_guard.c` (1369 lines, sha256 `07a27fd1...`, unchanged from Sprint 4 sweep commit)
- Binary: `bin/usernotify_exec_guard` (sha256 `e3bdaabf...`, unchanged from Sprint 4 sweep)
- Sprint 5 replay runs (this audit added one more):
  - `proofs/sprint5_runs/sprint5-docker-20260430T235602Z/` (first failed harness, preserved)
  - `proofs/sprint5_runs/sprint5-docker-20260430T235637Z/` (clean pass, superseded)
  - `proofs/sprint5_runs/sprint5-docker-20260430T235835Z/` (clean pass, superseded)
  - `proofs/sprint5_runs/sprint5-docker-20260501T000055Z/` (Sprint 5 self-claim: pass=6 fail=0)
  - `proofs/sprint5_runs/sprint5-docker-20260501T000703Z/` (Auditor A's re-run: pass=6 fail=0)
  - `proofs/sprint5_runs/sprint5-docker-20260501T000750Z/` (this audit's re-run: pass=6 fail=0)
- Sprint 2 replay run after Sprint 5: `proofs/sprint2_runs/sprint2-20260501T000833Z/` (pass=12 fail=0)
- Sprint 4 replay run after Sprint 5: `proofs/sprint4_runs/sprint4-20260501T000834Z/` (pass=22 fail=0)
- Sprint 4 audits (predecessors): `proofs/AUDIT_20260430_sprint4_independent_review_a.md`, `proofs/AUDIT_20260430_sprint4_independent_review_b.md`
- Sprint 3 audit (carry-forward source): `proofs/AUDIT_20260430_sprint3_independent_review.md`
