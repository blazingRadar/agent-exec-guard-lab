# Sprint 5 — Independent Audit Review (Auditor A)

Date: 2026-04-30
Auditor: Auditor A (independent adversarial pass after `SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`).
Posture: re-derive SHAs, re-run the Sprint 5 Docker harness live, re-run Sprint 2 and Sprint 4 regression replays, probe container-specific seccomp/Landlock interaction, check carry-forward and pre-registration discipline.
Source of record: live commands run on this host; SHAs re-derived; binary unchanged from Sprint 4; Docker daemon accessible via `sg docker -c`.
Parallel auditor: Auditor B running the same brief independently — no coordination.

---

## 1. Audit Question

Did Sprint 5 (a) deliver a real Docker integration proof — guard executing inside a container under Docker's default seccomp profile, with the Sprint 1–4 invariants surviving the namespace transition, (b) honestly preserve F4 deferral and OpenHands deferral disclosures, (c) carry forward the discipline established in Sprints 3 and 4, and (d) avoid claiming more than it actually demonstrated?

## 2. Verdict

**Sprint 5 delivers a real, reproducible "guard works inside a Docker container" proof. The headline as written is accurate but narrow — the operator already drafts it that way in the memo. The discipline gap is one that matters for this project's credibility argument: the gate document and the proof memo were committed in the same commit (`e972a70`) rather than the gate landing first. Pre-registration is asserted by the document framing but not by the git timeline.**

What is real:
- 6/6 Sprint 5 cases reproduced live by re-running `scripts/integration/replay_sprint5_docker_guard.sh`. New `run_root` `sprint5-docker-20260501T000703Z`. Identity-based BLOCK on a copied `/bin/rm` inside the container. Forged JSON written by the supervised child captured as `child_stderr` with proper `data:` framing and not as `event:exec_decision`.
- `seccomp(SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, …)` independently verified as permitted under Docker's default seccomp profile (`profile=builtin`, `Seccomp:2`) by an out-of-tree probe I built and ran in `python:3.12-slim`. `landlock_create_ruleset`, `landlock_add_rule`, and `landlock_restrict_self` all succeed inside the container under default seccomp (verified via `strace` of the guard).
- `/proc/<child_pid>/exe` resolves in the container's PID namespace (PID 7 / 8 / 13 in container, not host PIDs).
- Sprint 2 (12/12) and Sprint 4 (22/22) regressions still pass on the host after Sprint 5.
- F4 explicitly disclosed in both the gate and the proof memo.
- OpenHands 1.6.0 pinned by app+runtime image digests in the gate, the proof, and the command log.

What is overstated or incomplete:
- The gate is not pre-registered against git. `git log --diff-filter=A --follow proofs/SPRINT5_GATE_20260430.md` and the same against the proof memo and the harness all return the *same single commit* `e972a70 Sprint 5 Docker container integration proof`. The "pre-registration" semantics that the project's discipline argument leans on requires the gate to land *before* the harness/proof, in a separate earlier commit. This sprint's gate is best characterized as "drafted up front and committed alongside" rather than "filed before the work."
- The proof demonstrates interpretation **(a)** of the Sprint 5 brief — the guard binary is bind-mounted into a container and supervises an ordinary process inside that container. It does not yet demonstrate **(b)** — an agent process inside a container being supervised by the guard. The proof memo is honest about this ("Sprint 5B should run the same boundary against the pinned OpenHands runtime image"), but the headline framing "Docker container proof" could be read by a casual reader as the stronger claim.
- No Dockerfile is committed. The container is `docker run python:3.12-slim` directly with a bind mount. Image is pinned by the recorded digest `sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286`, but reproducibility is digest-pinning rather than build-from-source.
- `argv_total_count_capped` — the post-Sprint-4 sweep additions live in commit `2575f96`, so what Sprint 4 Auditor A flagged as A1–A4 was already absorbed before Sprint 5 began. Sprint 5 *could* have explicitly listed those in its Carry-forward table as "closed in 2575f96 sweep, not re-opened by container proof." It does not. Minor disclosure gap, not a regression.

The headline that survives this audit:

> "Sprint 5 demonstrates that the guard binary runs unchanged under Docker's default seccomp profile inside `python:3.12-slim`, supervises an in-container child, blocks a copied non-policy executable on identity, and demotes child-written forged JSON to `child_stderr`. Sprint 2 (12/12) and Sprint 4 (22/22) regressions still pass on the host. F4 (`SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU) remains explicitly deferred. OpenHands 1.6.0 is pinned by app and runtime image digests but the runtime image was not pulled this sprint. The container integration proof is interpretation (a) — guard-in-container — not (b) — agent-in-container-supervised-by-guard. (b) is the next gate."

Recommend: ship Sprint 5 as the in-container execution proof. Tighten the discipline claim by either landing the gate as a separate commit *before* future sprint proofs, or by adding an explicit "gate-and-proof committed together; pre-registration is by drafting, not by separate commit ordering" honesty line in the proof memo.

---

## 3. Discipline Check — Was the Gate Pre-Registered?

**Pre-registration by document framing: yes. Pre-registration by git history: no.**

```
$ git log --diff-filter=A --follow -- proofs/SPRINT5_GATE_20260430.md
commit e972a70af96938e82fee39b9acb0ce7eff2b47ef
Author: Nick Cunningham <nick.lee.cunningham@gmail.com>
Date:   Thu Apr 30 17:01:43 2026 -0700
    Sprint 5 Docker container integration proof

$ git log --diff-filter=A --follow -- proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
commit e972a70af96938e82fee39b9acb0ce7eff2b47ef
Author: Nick Cunningham <nick.lee.cunningham@gmail.com>
Date:   Thu Apr 30 17:01:43 2026 -0700
    Sprint 5 Docker container integration proof

$ git log --diff-filter=A --follow -- scripts/integration/replay_sprint5_docker_guard.sh
commit e972a70af96938e82fee39b9acb0ce7eff2b47ef
```

All three first-appear in the same commit. No prior commit registers the gate. The document itself is structured as a pre-registration ("Sprint 5 can claim integration only if all of these pass: 1. … 8. F4 is explicitly carried forward in the Sprint 5 memo"), and the acceptance criteria are not retro-fit — they precisely match what the harness and proof actually exercised. So the gate is *internally* a pre-registration; it just wasn't *temporally* one.

This is the load-bearing discipline question for the project's credibility argument and it is the cleanest finding in this audit. It does not invalidate the technical work; it weakens the procedural argument the project makes about how it conducts sprints.

**Carry-forward Open Items section present?** Yes, in both the gate (lines 11–18) and the proof memo (lines 7–14). Both list F4 plus two additional items (OpenHands full runtime; production-grade sandboxing) with status. Sprint 4 Auditor A items A1–A4 / Auditor B items B5–B6 from `2575f96` are *not* re-listed in the Sprint 5 carry-forward table. They were absorbed in `2575f96` (the same commit that landed the Sprint 4 audit memos), so they are not open items that should be carried forward — but a one-line acknowledgement ("post-Sprint-4 sweep items A1–A4 closed in `2575f96`; not re-opened by container proof") would have made the discipline visible. Minor disclosure gap.

---

## 4. What Verified Clean Independently

### 4.1 Re-derived SHAs

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
            policy/integration/docker_python_slim.allow.json \
            scripts/integration/replay_sprint5_docker_guard.sh \
            proofs/SPRINT5_GATE_20260430.md
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
7ccb1ceae281a50d0e50a6f7cd777c66adf863b6adbe1c1ede280254e8a2f8e6  policy/integration/docker_python_slim.allow.json
edbed7ca0eaed27300893354b9066c370b4d6ff175310bd6cce00d547ac8ff07  scripts/integration/replay_sprint5_docker_guard.sh
1f861067fae3a758c761b903d7458a5d8e7d40b79064d6cb07f5e0fd9f04d391  proofs/SPRINT5_GATE_20260430.md
```

All five match the values claimed in `SPRINT5_COMMAND_LOG_20260430.md`.

### 4.2 Line-count delta from Sprint 4

```
$ wc -l guard/usernotify_exec_guard.c
1369 guard/usernotify_exec_guard.c
$ git show 2575f96:guard/usernotify_exec_guard.c | wc -l
1369
```

Guard C source is **unchanged** from the post-sweep Sprint 4 state at commit `2575f96`. Sprint 5 added a harness, a policy file, and three memos — zero lines of guard code. The brief's "1258ish lines after the sweep" baseline is from the *initial* Sprint 4 commit `2cf79f0`, not from `2575f96`. The post-sweep Sprint 4 baseline is 1369; Sprint 5 leaves it at 1369. `+0` lines.

### 4.3 Live re-run of Sprint 5 Docker harness

```
$ bash scripts/integration/replay_sprint5_docker_guard.sh
PASS image_identity recorded
PASS allowed_python exit=0 json=valid
PASS blocked_renamed_rm exit=126 json=valid
PASS blocked_renamed_rm_output renamed rm did not execute
PASS stderr_forgery_contained exit=0 json=valid
PASS stderr_forgery_contained_check forgery captured as child_stderr
pass=6 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T000703Z
```

6/6 reproduced live. Image digest recorded as `sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286`, matching the proof memo.

`allowed_python` audit record (in-container PID = 7, container PID namespace, not host):

```
{"event":"exec_decision","timestamp":"2026-05-01T00:07:04.075Z","policy_id":"sprint5_docker_python_slim_allowlist_v1","pid":7,"syscall":59,"notif_id":2956343175611213488,"decision":"ALLOW","reason":"allowed_executable_identity","raw_exe":"/usr/local/bin/python3","realpath":"/usr/local/bin/python3.12","cwd":"/lab","dev":130,"ino":167117402,"sha256":"1904b016ee522c7ec76c8720cba47ab3eb68c32725345a056fcd7643118e7a42","argv":["/usr/local/bin/python3","--version"],"argv_truncated":false,"argv_total_count":2,"argv_total_count_capped":false}
```

`blocked_renamed_rm` audit record — `dev=66306` differs from `allowed_python`'s `dev=130` because the renamed binary lives on the bind-mounted host filesystem rather than the container image overlay; identity decision still BLOCK on SHA `c761a9dffe245730ee7a579bcf49006f8d94c98f55f6293283a566f903b6fc4a`:

```
{"event":"exec_decision",..."decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/lab/proofs/sprint5_runs/sprint5-docker-…/renamed_rm_python3","realpath":"/lab/proofs/sprint5_runs/sprint5-docker-…/renamed_rm_python3","dev":66306,"ino":62556448,"sha256":"c761a9dffe245730ee7a579bcf49006f8d94c98f55f6293283a566f903b6fc4a",…}
```

`stderr_forgery_contained` audit record — forged JSON is captured as `child_stderr` `data:` field, not as a top-level `event:exec_decision` reason:

```
{"event":"exec_decision",…,"decision":"ALLOW","reason":"allowed_executable_identity",…} ← real ALLOW from supervisor
{"event":"child_stderr",…,"data":"{\"event\":\"exec_decision\",\"decision\":\"ALLOW\",\"raw_exe\":\"/bin/rm\",\"reason\":\"FORGED_IN_CONTAINER\"}\n"} ← forgery framed
{"event":"supervisor_exit",…,"child_exit":0}
```

The F1 boundary is preserved end-to-end across the namespace transition.

### 4.4 Re-run regression gates on host

```
$ bash scripts/replay_sprint2_identity.sh
…
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint2_runs/sprint2-20260501T000748Z

$ bash scripts/replay_sprint4_audit_integrity.sh
…
pass=22 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint4_runs/sprint4-20260501T000749Z
```

Both regression suites still pass after Sprint 5. (Note: this is on the host, not inside the container — Sprint 5's regression claim is host-side, not in-container. See Section 5.2 for the in-container Sprint 1 basename probe.)

### 4.5 Docker default seccomp permits `seccomp(NEW_LISTENER)` — independent verification

I wrote a minimal probe in C, compiled it inside the container, and ran it under the default Docker seccomp profile:

```c
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER,
        SECCOMP_FILTER_FLAG_NEW_LISTENER, &prog);
```

```
$ sg docker -c "docker run --rm -v /tmp/seccomp_probe.c:/probe.c:ro python:3.12-slim sh -c \
   'apt-get update >/dev/null 2>&1 && apt-get install -y -qq gcc libc6-dev linux-libc-dev >/tmp/apt.log 2>&1 && \
    gcc /probe.c -o /probe && /probe; echo rc=\$?'"
seccomp(NEW_LISTENER) returned listener_fd=3
rc=0
```

Verified: under Docker's default seccomp profile (`profile=builtin`), an unprivileged caller in a non-`--privileged`, non-`seccomp=unconfined` container CAN install a new seccomp filter with `NEW_LISTENER`. This makes the operator's load-bearing claim — "the guard runs under Docker's default seccomp profile" — independently true.

### 4.6 Landlock works inside container under default Docker seccomp

```
$ sg docker -c "docker run --rm … strace -e seccomp,landlock_…,prctl … /lab/bin/usernotify_exec_guard …"
[pid 81] seccomp(SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, …) = 3
[pid 81] landlock_create_ruleset({handled_access_fs=LANDLOCK_ACCESS_FS_EXECUTE, …}, 16, 0) = 3
[pid 81] landlock_add_rule(3, LANDLOCK_RULE_PATH_BENEATH, …) = 0  (×7)
[pid 81] landlock_restrict_self(3, 0) = 0
```

Default Docker seccomp does not block the `landlock_*` syscalls. Sprint 3's Landlock layer survives containerization. Verified live.

### 4.7 In-container Sprint 1 basename bypass remains blocked

```
$ sg docker -c "docker run --rm -v … python:3.12-slim sh -c 'cp /bin/rm /tmp/git; chmod 755 /tmp/git; \
   /lab/bin/usernotify_exec_guard --policy /lab/policy/integration/docker_python_slim.allow.json /tmp/git --version'"
{"event":"exec_decision",…,"decision":"BLOCK","reason":"blocked_executable_identity","raw_exe":"/tmp/git","realpath":"/tmp/git",…,"sha256":"c761a9dffe245730ee7a579bcf49006f8d94c98f55f6293283a566f903b6fc4a",…}
…rc=126
```

Sprint 1 invariant (basename-of-`/bin/rm` blocked under any name) holds inside the container.

### 4.8 SHA-256 (AF_ALG) computed inside container

Inside the container, `sha256` field of the `exec_decision` JSON is a real 64-hex-digit hash, e.g. `1904b016ee522c7ec76c8720cba47ab3eb68c32725345a056fcd7643118e7a42` for `python3.12`. AF_ALG works without network namespace privileges (it is a `socket(AF_ALG, …)` call, not a `socket(AF_INET, …)` call). F6 survives containerization.

---

## 5. Critical Findings

**None that block keeping Sprint 5.** The discipline finding in Section 3 is the closest the audit comes; it's a procedural gap, not a technical one.

The operator's own "Claims Now Allowed" / "Claims Still Not Allowed" split in `SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` is the most concise honest summary. I would not tighten it further; the operator has already pre-tightened it.

---

## 6. Container-Specific Findings (Sprint 5's New Surface)

### 6.1 `/proc/<child_pid>/exe` correctly resolves in the container's PID namespace

```
$ # inside container, with guard supervising python3 -c "print(os.getpid(), os.getppid())"
pid= 8 ppid= 7
```

The guard is PID 7 (container's PID namespace), the supervised child is PID 8. The audit records show `pid:7` (allowed_python) and `pid:13` (blocked_renamed_rm). All small integers, all from the container's `/proc`. Not host PIDs. F5 closure survives the namespace transition.

### 6.2 `dev` field reflects the bind-mount overlay correctly

`allowed_python` records `dev=130`, which is the python image overlay layer. `blocked_renamed_rm` records `dev=66306`, which is the bind-mounted host filesystem under `/lab`. The dev/ino identity decision uses the *container's view* of the filesystem, not the host's — this is the right semantics. A copy across overlay/bind boundaries gets a fresh `dev`+`ino` and a fresh SHA-256, all of which are recorded.

### 6.3 Default Docker seccomp permits `seccomp(NEW_LISTENER)` and `landlock_*` — verified

See Sections 4.5 and 4.6. The default profile is permissive enough for the guard to install both layers. No `--security-opt` flag was needed in the harness; verified by inspecting `scripts/integration/replay_sprint5_docker_guard.sh` (no occurrences of `--security-opt`, `seccomp=unconfined`, or `--privileged`).

### 6.4 Bind-mounted guard binary — out of threat model, but worth a note

The harness mounts the host's `bin/usernotify_exec_guard` into the container at `/lab/bin/usernotify_exec_guard` with `:rw`. An operator overriding that path with a different binary — or making the bind mount writable from inside the container and replacing the file mid-run — would defeat the guard. This is out of the guard's threat model (the operator is trusted) but worth a one-line acknowledgement in the proof memo for the OpenHands handoff sprint, where the operator-supplied integration boundary becomes load-bearing.

### 6.5 Container-namespace exit attempts

Not probed live. The seccomp filter intercepts `execve`/`execveat`; it does not directly affect `unshare`, `setns`, `clone(CLONE_NEW*)` or other namespace operations. A malicious supervised child cannot escape the container by virtue of seccomp-user-notify alone — that is Docker's job, not the guard's. The guard does not introduce a new namespace-escape vector; the syscall filter list is exec-only. No finding.

### 6.6 cgroup CPU limits and signal-handler timing

Not probed live. The signal handler in the post-sweep guard is async-signal-safe (per Sprint 4 Auditor A item A4 closure in `2575f96`) — it writes a precomputed string and `_exit`s. cgroup CPU throttling could in principle delay the supervisor's response to a signal, but the audit-correctness invariant (handler emits `supervisor_exit{reason:killed_by_signal}`) does not depend on prompt scheduling. No finding.

---

## 7. F4 Deferral and OpenHands Handoff State

**F4 carry-forward.** Verified present in:
- `proofs/SPRINT5_GATE_20260430.md`: "F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred. Sprint 5 does not attempt `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. It must be named in all claims."
- `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`: "F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred and still disclosed. Sprint 5 does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`."
- `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` "Claims Still Not Allowed": "No claim that F4 is fixed."

Three independent disclosures. Discipline preserved.

**OpenHands handoff state.** The 1.6.0 pin is recorded in:
- `SPRINT5_GATE_20260430.md`: release tag, release date, app and runtime image manifests.
- `SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`: app manifest digest `sha256:5c0dc26f467bf8e47a6e76308edb7a30af4084b17e23a3460b5467008b12111b`, runtime amd64 digest `sha256:4959cef8059841fa5bf05fb1368d9ce5735d0ba94b2a3ceee335285e26529452`.
- `SPRINT5_COMMAND_LOG_20260430.md`: same digests, plus the `gh repo view` and `docker manifest inspect` commands used to obtain them.

The runtime image was *not* pulled this sprint. The proof memo names this explicitly: "The OpenHands runtime image is about 2.28 GB compressed for amd64, so this sprint did not pull it as part of the first container proof." Honest. Sprint 5B is gated on actually pulling and exercising that runtime.

---

## 8. Sprint 6 (or Sprint 5B) Prerequisites

In approximate priority order:

1. **Pre-register the next gate as a separate commit before the proof commit.** The procedural complaint of this audit. One commit `Sprint 5B gate: OpenHands 1.6.0 runtime integration` should land before any commit that introduces a runtime image, harness, or memo for Sprint 5B. This is the only way the pre-registration framing carries weight in git history.

2. **Pull `ghcr.io/openhands/runtime:1.6.0-nikolaik` (or the app image) and pin it by local-store digest.** Demonstrate the digest the harness will use, not just the digest the registry returns.

3. **Decide and document interpretation (a) vs (b) explicitly in the next gate.** Sprint 5 is unambiguously (a). Sprint 5B should make explicit which it is — agent-in-container-supervised-by-guard would be (b), and that's the OpenHands-load-bearing case. Don't conflate the two.

4. **One-line carry-forward of post-Sprint-4 sweep items.** Even though A1–A4 / B5–B6 closed in `2575f96`, a brief note in the next sprint's Carry-forward Open Items table ("post-Sprint-4 sweep items closed in `2575f96`; not re-opened by container proof") would make discipline visible without bloating the table.

5. **Operator-side bind-mount note.** The guard binary is bind-mounted from host. For OpenHands integration, document the operator-supplied integration boundary explicitly as out-of-threat-model.

6. **F4 architecture work remains the standing carry-forward.** Not gated on Sprint 5B.

---

## 9. Honest Headline

**The current claim ("guard runs inside Docker under default seccomp; copied/renamed `/bin/rm` blocked; child-written forged JSON captured as `child_stderr`; F4 deferred; OpenHands pinned but not pulled") is accurate.** The proof memo's `## Claim Now Allowed` paragraph (lines 87–89) is already tight:

> "A local seccomp user-notify plus Landlock execution guard can run inside a Docker container under Docker's default seccomp profile, allow an approved container executable, block a copied non-policy executable before it runs, and preserve the Sprint 4 audit-forgery boundary by demoting child-written JSON to `child_stderr`."

I would not tighten it further. The one sentence I would *add* to the proof memo for full discipline:

> "Note: the gate document and this proof memo were committed in the same git commit `e972a70`. The acceptance criteria were drafted up front but were not landed as a separate earlier commit. Pre-registration here is by document framing, not by commit ordering. Future sprints should land the gate as a separate prior commit."

That single addition closes the discipline gap this audit found.

---

## 10. Commands Used For This Audit

```
$ git log --oneline -20
e972a70 Sprint 5 Docker container integration proof
78680af Tighten Sprint 4 audit fidelity disclosures
2575f96 Sprint 4 audit memos + post-audit sweep hardening
2cf79f0 Initial auditable agent exec guard lab

$ git log --diff-filter=A --follow -- proofs/SPRINT5_GATE_20260430.md
$ git log --diff-filter=A --follow -- proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md
$ git log --diff-filter=A --follow -- scripts/integration/replay_sprint5_docker_guard.sh
   → all three: only commit e972a70

$ git log --format='%H %ai %s' --all
e972a70 2026-04-30 17:01:43 -0700 Sprint 5 Docker container integration proof
78680af 2026-04-30 16:47:48 -0700 Tighten Sprint 4 audit fidelity disclosures
2575f96 2026-04-30 16:45:04 -0700 Sprint 4 audit memos + post-audit sweep hardening
2cf79f0 2026-04-30 16:28:50 -0700 Initial auditable agent exec guard lab

$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
            policy/integration/docker_python_slim.allow.json \
            scripts/integration/replay_sprint5_docker_guard.sh \
            proofs/SPRINT5_GATE_20260430.md
07a27fd1…  guard/usernotify_exec_guard.c
e3bdaabf…  bin/usernotify_exec_guard
7ccb1cea…  policy/integration/docker_python_slim.allow.json
edbed7ca…  scripts/integration/replay_sprint5_docker_guard.sh
1f861067…  proofs/SPRINT5_GATE_20260430.md

$ wc -l guard/usernotify_exec_guard.c
1369

$ git show 2575f96:guard/usernotify_exec_guard.c | wc -l
1369

$ bash scripts/integration/replay_sprint5_docker_guard.sh
   → pass=6 fail=0
   → run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint5_runs/sprint5-docker-20260501T000703Z

$ bash scripts/replay_sprint2_identity.sh
   → pass=12 fail=0

$ bash scripts/replay_sprint4_audit_integrity.sh
   → pass=22 fail=0

$ sg docker -c "docker info --format '{{.SecurityOptions}}'"
[name=apparmor name=seccomp,profile=builtin name=cgroupns]

$ sg docker -c "docker run --rm python:3.12-slim sh -c 'grep -E ^Seccomp /proc/self/status'"
Seccomp:	2
Seccomp_filters:	1

$ # Independent seccomp(NEW_LISTENER) probe inside default-seccomp container:
$ sg docker -c "docker run --rm -v /tmp/seccomp_probe.c:/probe.c:ro python:3.12-slim sh -c \
   'apt-get update >/dev/null 2>&1 && apt-get install -y -qq gcc libc6-dev linux-libc-dev … && \
    gcc /probe.c -o /probe && /probe'"
seccomp(NEW_LISTENER) returned listener_fd=3
rc=0

$ # In-container strace of guard:
$ sg docker -c "docker run --rm -v … strace -e seccomp,landlock_create_ruleset,landlock_add_rule,\
   landlock_restrict_self,prctl … /lab/bin/usernotify_exec_guard …"
seccomp(SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, …) = 3
landlock_create_ruleset(…) = 3
landlock_add_rule(…) = 0   (×7)
landlock_restrict_self(3, 0) = 0

$ # Sprint 1 basename bypass inside container:
$ sg docker -c "docker run --rm … sh -c 'cp /bin/rm /tmp/git; chmod 755 /tmp/git; \
   /lab/bin/usernotify_exec_guard --policy …/docker_python_slim.allow.json /tmp/git --version'"
{"event":"exec_decision",…,"decision":"BLOCK","reason":"blocked_executable_identity",
 "raw_exe":"/tmp/git","sha256":"c761a9dffe245730…",…}
rc=126

$ # In-container PID namespace check:
$ sg docker -c "docker run --rm … sh -c '/lab/bin/usernotify_exec_guard … /usr/local/bin/python3 \
   -c \"import os; print(os.getpid(), os.getppid())\"'"
pid= 8 ppid= 7

$ # Cleanup:
$ rm -f /tmp/seccomp_probe.c /tmp/audit_a_analyzer
```

No retained `/tmp` artifacts. All in-container probes are stateless `--rm` runs.
