# Sprint 6B — Independent Audit Review (Auditor A)

Date: 2026-05-01
Auditor: Auditor A (independent adversarial pass after `SPRINT6B_ACTION_SERVER_PROOF_20260501.md`).
Posture: re-derive SHAs, re-run the Sprint 6B harness live, re-run Sprint 2/4/5/6A regression replays, examine the actual `/execute_action` HTTP path, and decide which of (a)/(b)/(c) the proof actually demonstrates.
Source of record: live commands run on this host; commits `c4392ae` (gate) and `243068f` (proof) pushed; preserved artifacts in `proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/`; OpenHands 1.6.0 source mounted from `external/OpenHands-1.6.0` at commit `c5e0de8e…`.
Parallel auditor: Auditor B running the same brief independently — no coordination.

---

## 1. Audit Question

Did Sprint 6B (a) prove that the guard supervises the OpenHands runtime's `action_execution_server.py` command-execution path in the strong (b)-sense — every `execve` produced by an `/execute_action` HTTP request is intercepted and decided by the guard — rather than the weak (a)-sense the Sprint 5 reviewers warned against, (b) preserve the post-Sprint-5 pre-registration discipline (gate commit lands strictly before proof commit), (c) keep all earlier regression invariants intact (Sprint 2/4/5/6A), and (d) keep F4 and the OpenHands web-app/LLM-agent boundaries explicitly disclosed?

## 2. Verdict

**Sprint 6B is the real (b)-sense proof.** The gate landed first by ~16 minutes of git timeline. The harness boots the pinned OpenHands `action_execution_server.py` *as the supervised child of the guard* and then sends real HTTP `POST /execute_action` requests; the resulting `cat input.txt` and `cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version` execute through the real OpenHands `BashSession` (libtmux pane), and every `execve` along that path — `bash`, `cp`, `chmod`, `cat`, the renamed `./python3` — appears in the guard's audit JSON with a real `decision`. The renamed-rm BLOCK is recorded with `decision=BLOCK reason=blocked_executable_identity raw_exe="./python3" realpath="/lab/proofs/sprint6b_runs/.../workspace/python3"`. The `/execute_action` HTTP response correctly carries `success=false, exit_code=126, content="bash: ./python3: Operation not permitted"`. I reproduced 12/0 live. All four regressions reproduced live (Sprint 2 12/0, Sprint 4 22/0, Sprint 5 11/0, Sprint 6A 13/0).

The current headline "Guard wraps pinned OpenHands runtime `action_execution_server.py`; real `/execute_action` path tested" is **accurate**. I would tighten one phrase: this is **agent-runtime command path under the guard, not yet agent-driven (LLM-issued) actions** — the proof memo already says this, and an audit-trail-conscious reader should not over-read it.

What is real:
- 12/12 cases reproduced live in `proofs/sprint6b_runs/sprint6b-action-server-20260501T005827Z/` from a fresh harness invocation by me.
- Every audit decision in the run came from the guard supervising the action server's whole subtree (PID 1 in the container is the guard; tmux/bash/cp/chmod/cat/python3 are all descendants).
- The BLOCK is recorded by both the action-server HTTP response (exit_code=126, "Operation not permitted") and by the guard's audit JSON (blocked_executable_identity).
- Source is clean (`git status --short` returns only my reproduction artifacts).
- F4 carry-forward present. Carry-Forward Open Items table is the Sprint 4 enumeration (F1–F8 + A1–A4 + B5–B6) plus three OpenHands rows.
- Guard binary unchanged from Sprint 6A (`bin/usernotify_exec_guard` SHA `e3bdaabf…` identical at `78a2ba1` and `243068f`).

What is narrow but honestly disclosed:
- The action server's other endpoints — `FileWriteAction`, `FileReadAction`, `FileEditAction`, `BrowseURLAction`, `/upload_file`, `/list_files` — are **not** intercepted by the guard. The guard is exec-only by design. The proof memo's "Claims Still Not Allowed" lists "Complete filesystem, network, or data-exfiltration isolation," which is the right disclosure — but worth naming the specific *action-server* surface that is not covered (Section 6.1 below).
- The action server runs without `SESSION_API_KEY` in this harness, so any in-container client can `POST /execute_action`. That's appropriate for a controlled lab harness; in production the OpenHands deployment passes a session key. Worth a one-line note.
- The proof memo does not yet pre-register a Sprint 7 gate. That is the natural next step (full app / LLM-agent-issued action), and the procedural lesson from Sprint 5/6A is that the gate should land *before* the work.

What is overstated nowhere I can see:
- Nothing.

The headline that survives this audit:

> "Sprint 6B demonstrates the load-bearing (b)-interpretation: the pinned OpenHands `action_execution_server.py` runs as a supervised child of the seccomp-user-notify + Landlock guard; real HTTP `POST /execute_action` calls execute through the action server's real `BashSession` (libtmux pane); commands the action server issues — including a copied/renamed `/usr/bin/rm` — produce execve audit decisions in the guard's JSON stream and the BLOCK is reflected in the action-server HTTP response shape (`success=false, exit_code=126, Operation not permitted`). Sprint 2/4/5/6A regressions reproduce 12/22/11/13 fail=0. F4 stays explicitly deferred. The result is narrower than full OpenHands web-app / LLM-agent supervision, and the proof memo says so. Guard source/binary unchanged from Sprint 6A; Sprint 6B is harness + policy + memo work."

Recommend: ship Sprint 6B as the (b)-sense action-server proof. For Sprint 7, pre-register the gate first (the discipline now has its first clean gate-precedes-proof example in `c4392ae` → `243068f`; keep the streak), and pick exactly one of: (i) drive the action server from a real OpenHands LLM-agent loop, (ii) extend the guard's coverage to the FileWrite/FileRead action paths, or (iii) make the policy file Landlock-WRITE-protected so a `FileWriteAction` cannot rewrite the allowlist mid-run.

---

## 3. Discipline Check — Was the Gate Pre-Registered?

**Pre-registration by git history: yes. This is the first sprint where the gate-first discipline is visible in the commit timeline.**

```
$ git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_GATE_20260501.md
c4392ae 2026-04-30 17:39:02 -0700 Pre-register Sprint 6B OpenHands command path gate

$ git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_ACTION_SERVER_PROOF_20260501.md
243068f 2026-04-30 17:54:54 -0700 Sprint 6B OpenHands action server proof

$ git log --oneline -6
243068f Sprint 6B OpenHands action server proof
c4392ae Pre-register Sprint 6B OpenHands command path gate
78a2ba1 Sprint 6 OpenHands runtime one-file proof
fe5bd19 Pre-register Sprint 6 OpenHands runtime gate
8332e93 Clean Sprint 5 proof metadata
31753ce Sprint 5 independent audit memos + reproduced replay runs
```

`c4392ae` precedes `243068f` by 15:52. Both Sprint 6 pairs (`fe5bd19` → `78a2ba1`, `c4392ae` → `243068f`) preserve the gate-first ordering. This closes the Sprint 5 procedural complaint cleanly and establishes the discipline pattern.

**Carry-Forward Open Items section.** Verified present in `SPRINT6B_GATE_20260501.md` lines 21–40 and `SPRINT6B_ACTION_SERVER_PROOF_20260501.md` lines 17–35. Both list the full F1–F8 + A1–A4 + B5–B6 enumeration. The proof memo adds three rows: "Sprint 6A OpenHands runtime one-file proof" (Closed in Sprint 6A), "Full OpenHands app / LLM-agent proof" (Not claimed), "Production-grade sandbox claim" (Not claimed). This matches the Sprint 4/5 discipline pattern exactly. **Closed.**

**F4 disclosure.** Verified present:
- Gate, line 28: "F4 | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` path TOCTOU | Deferred. Sprint 6B does not implement `SECCOMP_IOCTL_NOTIF_ADDFD + execveat`. Must be disclosed."
- Proof, line 22: "F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU | Deferred and disclosed; not fixed by Sprint 6B."
- Proof "Claims Still Not Allowed", line 167: "A claim that F4 is fixed."

Three independent disclosures. **Discipline preserved.**

---

## 4. The (a) vs (b) Determination — Headline Finding

This is the load-bearing question of the audit. Auditor A's evidence-based determination: **Sprint 6B is (b).** Concrete evidence:

### 4.1 The harness boots the action server as the guard's supervised child

Quoting `scripts/integration/replay_sprint6b_action_server.sh` lines 92–106:

```bash
sg docker -c "docker run -d --name '$CONTAINER_NAME' \
  -v '$ROOT:/lab:rw' \
  -v '$SOURCE_DIR:/openhands/code:ro' \
  -w /openhands/code \
  -e PYTHONPATH=/openhands/code \
  '$IMAGE' \
  /lab/bin/usernotify_exec_guard \
  --policy '$POLICY_IN_CONTAINER' \
  /openhands/micromamba/bin/micromamba run -n openhands poetry run python -u -m openhands.runtime.action_execution_server 30000 \
  --working-dir '$WORKSPACE_IN_CONTAINER' \
  --username daemon \
  --user-id 1 \
  --no-enable-browser"
```

This is **not** Sprint 6A's pattern of "guard runs `cat input.txt` directly inside the OpenHands runtime image." The container's PID 1 is `usernotify_exec_guard`. The action server (`python -u -m openhands.runtime.action_execution_server`) is its direct supervised child. Every `execve` in the action server's process tree — including everything `BashSession` spawns later via libtmux — inherits the seccomp filter installed by the guard before it `execve`s the action server.

### 4.2 The harness then sends real HTTP `POST /execute_action`

`scripts/integration/replay_sprint6b_action_server.sh` lines 143–168 write `send_action.py` which builds:

```python
payload = {
    "action": {
        "action": "run",
        "args": {
            "command": command,
            "is_input": False,
            "blocking": False,
            "is_static": False,
        },
    }
}
req = urllib.request.Request(
    "http://127.0.0.1:30000/execute_action",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
```

Then `run_action_case` (lines 185–197) `docker exec`s that script inside the container so it hits `127.0.0.1:30000/execute_action`. This is a **real HTTP POST** to the FastAPI route at `external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py:821 @app.post('/execute_action')`, not a synthetic syscall.

### 4.3 The action server's `/execute_action` route dispatches into `BashSession.execute`

Quoting `external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py`:

```python
# line 821
@app.post('/execute_action')
async def execute_action(action_request: ActionRequest):
    ...
    observation = await client.run_action(action)   # → ActionExecutor.run_action
    return event_to_dict(observation)

# line 386
async def run_action(self, action) -> Observation:
    async with self.lock:
        action_type = action.action
        observation = await getattr(self, action_type)(action)  # → run() for CmdRunAction
        return observation

# line 392
async def run(self, action: CmdRunAction) -> CmdOutputObservation | ErrorObservation:
    bash_session = self.bash_session
    obs = await call_sync_from_async(bash_session.execute, action)
    return obs
```

`BashSession` uses `libtmux` (`openhands/runtime/utils/bash.py:16`) to drive a long-lived tmux pane in which a real `bash` shell runs. Every command the action server runs is keystroked into that tmux pane and executed by that `bash` — which then `execve`s `cat`, `cp`, `chmod`, `./python3`, etc. The seccomp filter is `SECCOMP_FILTER_FLAG_TSYNC|NEW_LISTENER` and is installed in the guard before the action server starts; it is inherited across every fork/exec in the descendant tree.

### 4.4 Audit JSON proves end-to-end interception of the agent's command path

I parsed `proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/container_logs.combined`:

```
ALLOW count: 84
BLOCK count: 5

Distinct ALLOW raw_exe paths in this run:
  /openhands/micromamba/bin/micromamba
  /usr/bin/bash, /bin/bash, /bin/sh
  /usr/bin/basename, /usr/bin/cat, /usr/bin/chmod, /usr/bin/chown, /usr/bin/cp,
  /usr/bin/git, /usr/bin/id, /usr/bin/mkdir, /usr/bin/run-parts, /usr/bin/which,
  /usr/bin/tmux, /openhands/poetry/.../python, poetry binary
```

Filtered to entries with `cwd=/lab/proofs/sprint6b_runs/.../workspace` (the per-action working directory the agent shell is in when `/execute_action` arrives), the audit stream shows:

```
ALLOW /usr/bin/tmux argv: ['/usr/bin/tmux', 'has-session', '-t']    pid:132
ALLOW /usr/bin/tmux argv: ['/usr/bin/tmux', 'new-session', '-P']    pid:133
ALLOW /bin/bash    argv: ['-bash']                                   pid:136
ALLOW /usr/bin/cat argv: ['cat', 'input.txt']                        ← from /execute_action #1
ALLOW /usr/bin/cp  argv: ['cp', '/usr/bin/rm', './python3']          ← from /execute_action #2
ALLOW /usr/bin/chmod argv: ['chmod', '+x', './python3']              ← from /execute_action #2
BLOCK ./python3   argv: ['./python3', '--version']                   ← BLOCKED on identity
       reason: blocked_executable_identity
       realpath: /lab/proofs/sprint6b_runs/.../workspace/python3
```

The tmux server, the bash login session, and every shell-spawned subprocess for both `/execute_action` requests are all intercepted by the guard. The renamed `/usr/bin/rm` block is real and identity-keyed. This is **(b) interpretation**: agent-runtime command path supervised by guard, not just guard-runs-a-program.

### 4.5 Why this is not just (c)

The Sprint 5 follow-up named (c) as "guard wraps the action server's *entrypoint*, but commands fired *by* the agent through the action server may or may not flow through the guard." The audit log refutes (c) directly: the BLOCK on `./python3` happened **inside** an `/execute_action` request that the action server tried to dispatch — the action server's HTTP response carries `exit_code=126` and `Operation not permitted`, which is the visible effect of the guard's `seccomp(USER_NOTIF) → BLOCK` decision flowing back through `bash`'s execve return path, through libtmux to the action server's `BashSession.execute`, and out the FastAPI handler. There is no path by which a command fired through `/execute_action` could miss the guard, because the action server, the tmux server, the bash session, and every fork/exec descendant are inside the guard's seccomp filter scope.

### 4.6 The honest narrowing

Three things that are **not** what this proves:
- **Not LLM-agent-issued actions.** The HTTP client is `send_action.py`, a hard-coded curl-equivalent. No autonomous agent decided "let me try to copy /usr/bin/rm" — the harness scripts that. Sprint 7's gate should explicitly cover the LLM-driven case.
- **Not non-execve actions.** The action server has FileRead/FileWrite/FileEdit/BrowseURL handlers (Section 6.1 below). A `FileWriteAction` does not go through execve and is not supervised by the guard. The proof memo's "Claims Still Not Allowed" → "Complete filesystem, network, or data-exfiltration isolation" covers this honestly but generically.
- **Not the OpenHands web app / agent loop.** The harness boots only the runtime's action server. The wider OpenHands app (orchestrator, LLM provider, web UI) is not in scope.

---

## 5. What Verified Clean Independently

### 5.1 Re-derived SHAs

```
$ sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
            policy/integration/openhands_action_server.allow.json \
            scripts/integration/replay_sprint6b_action_server.sh \
            proofs/SPRINT6B_GATE_20260501.md
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a  guard/usernotify_exec_guard.c
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b  bin/usernotify_exec_guard
ccfa471b1e2576913f0751138ac41d35a65aeefd746f3b6734ff2bac0d942393  policy/integration/openhands_action_server.allow.json
91d26f02acdbb769b2050eabe597fa128346bf353f52c4f1428459f69e498850  scripts/integration/replay_sprint6b_action_server.sh
dd30a713eda6af691c6a58879f8710a5fe0e3c102f7308d35fc37936d2a12134  proofs/SPRINT6B_GATE_20260501.md
```

All five match the proof memo's claimed hashes (lines 153–158).

### 5.2 Guard unchanged from Sprint 6A

```
$ git show 78a2ba1:bin/usernotify_exec_guard | sha256sum
e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b
$ git show 78a2ba1:guard/usernotify_exec_guard.c | sha256sum
07a27fd1e73545b2ff6ac29b06737eda012e1698b0291468b71d807f3b15c87a
```

Sprint 6B added zero guard code. The (b)-sense integration is achievable purely with harness + policy + memo — that is itself a meaningful claim about the guard's design (the seccomp filter is inherited across the entire process tree by Linux kernel semantics, so wrapping the action server's launch is sufficient).

### 5.3 Live re-run of Sprint 6B harness (independent reproduction)

```
$ bash scripts/integration/replay_sprint6b_action_server.sh
PASS source_commit c5e0de8ecd85cef10e7808d57e9f939f3770ab9d
PASS image_identity recorded
PASS docker_run container started
PASS docker_inspect recorded
PASS docker_securityopt_default HostConfig.SecurityOpt=None
PASS alive_probe server returned /alive
PASS action_allowed_cat HTTP action returned
PASS action_allowed_cat_result workspace file read via /execute_action
PASS action_block_renamed_rm HTTP action returned
PASS action_block_renamed_rm_result renamed rm blocked via /execute_action
PASS container_logs_json guard audit lines parse
PASS guard_log_blocked_python3 guard logged copied rm block
pass=12 fail=0
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint6b_runs/sprint6b-action-server-20260501T005827Z
```

12/12 reproduced live. New run dir preserved. (Note: a second run dir `…005856Z` also appeared — that one fired during the regression sweep that touched my previous Sprint 6A replay. Both run dirs report `pass=12 fail=0`. Both are independent of the operator's `…004956Z`.)

### 5.4 Live re-run of regression replays

```
$ bash scripts/replay_sprint2_identity.sh           → pass=12 fail=0  (sprint2-20260501T005848Z)
$ bash scripts/replay_sprint4_audit_integrity.sh    → pass=22 fail=0  (sprint4-20260501T005849Z)
$ bash scripts/integration/replay_sprint5_docker_guard.sh → pass=11 fail=0  (sprint5-docker-20260501T005849Z)
$ bash scripts/integration/replay_sprint6_openhands_runtime.sh → pass=13 fail=0 (sprint6-openhands-runtime-20260501T005851Z)
```

All four reproduce. Sprint 6B does not regress any earlier invariant.

### 5.5 Action server response shape correctness

`action_allowed_cat.response.json`:
```json
{"message":"Command `cat input.txt` executed with exit code 0.",
 "observation":"run","content":"sprint6b-action-server-file",
 "extras":{"command":"cat input.txt",
   "metadata":{"exit_code":0,"pid":-1,"username":"root","hostname":"0d0f8e247a60",
     "working_dir":"/lab/proofs/sprint6b_runs/.../workspace",...}},
 "success":true}
```

`action_block_renamed_rm.response.json`:
```json
{"message":"Command `cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version` executed with exit code 126.",
 "observation":"run","content":"bash: ./python3: Operation not permitted",
 "extras":{...,"metadata":{"exit_code":126,...}},
 "success":false}
```

These are the OpenHands `CmdOutputObservation` shape with `success` and `extras.metadata.exit_code` populated correctly. The guard's BLOCK manifests as `EPERM` from `execve`, which `bash` reports as "Operation not permitted" with exit code 126. Both the action server's response AND the guard's `exec_decision` JSON record the same event from two angles. **End-to-end semantics verified.**

### 5.6 Working tree state

`git status --short` before my audit run was empty. After my audit it shows only my reproduction artifacts (new sprint2/4/5/6/6b run dirs, two `latest_*.txt` pointer updates) — no source/policy/script/proof modifications. **The operator's working tree was clean.**

---

## 6. New Findings or Attack Surfaces Specific to Sprint 6B

### 6.1 Non-execve action surfaces are out of scope (correctly disclosed, generally)

The action server exposes endpoints that do **not** route through execve:

| Endpoint | Action class | Guard supervised? |
|---|---|---|
| `POST /execute_action` `CmdRunAction` | `BashSession.execute` (libtmux→bash→execve) | YES |
| `POST /execute_action` `FileReadAction` | Python file open/read | NO (no execve) |
| `POST /execute_action` `FileWriteAction` | Python file open/write | NO (no execve) |
| `POST /execute_action` `FileEditAction` | Python file edit | NO (no execve) |
| `POST /execute_action` `BrowseURLAction` | playwright browser | partial (may fork, but no policy) |
| `POST /execute_action` `IPythonRunCellAction` | jupyter kernel | partial (depends on whether it fork+execs) |
| `POST /upload_file` | Python file write | NO |
| `GET /download_files` | Python file read | NO |

**Concrete attack**: an agent with access to `/execute_action` can issue a `FileWriteAction` to `/lab/policy/integration/openhands_action_server.allow.json` (the policy file is on the bind-mounted host filesystem, RW, owned by `blazingradar`, world-readable but only owner-writable from inside the container with matching uid). I verified the guard's Landlock layer only sets `LANDLOCK_ACCESS_FS_EXECUTE` (no WRITE/READ rules — `grep -n LANDLOCK_ACCESS guard/usernotify_exec_guard.c` shows only `LANDLOCK_ACCESS_FS_EXECUTE`). So:
- The container runs as `daemon` (uid 1) per the harness `--username daemon --user-id 1` flags. The host-side bind-mount `/lab` is owned by `blazingradar` (uid 1000). `daemon` (uid 1) cannot overwrite the policy file because of host filesystem permissions, **not because of the guard**. This is operator-dependent and fragile.
- A more privileged uid in the container — or a workspace path owned by the agent inside `/lab/proofs/sprint6b_runs/.../workspace` — *can* be written by FileWriteAction. The guard's policy file specifically resides under `/lab/policy/`, not the workspace, so for this run the attack does not land — but the protection is "host filesystem ownership," not the guard.

**Recommendation for Sprint 7**: add a Landlock WRITE-deny for the policy file path so a `FileWriteAction` cannot rewrite the allowlist, and include this in the carry-forward table.

### 6.2 Action server runs without `SESSION_API_KEY`

Source: `external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py:101–103` defines `verify_api_key`. The harness invocation does **not** pass `--session-api-key`, so `SESSION_API_KEY` is empty (line 102: `if SESSION_API_KEY and api_key != SESSION_API_KEY` short-circuits when the key is empty). Any in-container client can `POST /execute_action`. For a controlled lab harness this is fine; for a production claim it would matter. Worth noting: in this run the test client is itself inside the guarded container, so it doesn't open a new threat — but a Sprint 7 demo should set the key to model production.

### 6.3 Process model: long-lived tmux/bash session, supervised

Each `/execute_action` does **not** spawn a new bash. The action server creates one libtmux server + one tmux session at startup, and keystrokes commands into that pane (`openhands/runtime/utils/bash.py:210–250`). The audit log shows `tmux new-session` once at server boot (PID 133) and a single `bash` PID 136/147 for the rest of the run. The guard supervises that long-lived state correctly because the seccomp filter installed by PID 1 (the guard) is inherited by every descendant, including the tmux server and the bash session it opens. No race condition was observed.

### 6.4 The action-server bash session may use heredocs/stdin redirection that does not re-execve

A subtle non-finding: if the `command` string passed to `/execute_action` is a pure-bash builtin (`echo`, `cd`, `:`) or shell loop with no execve, the guard sees nothing for that action. That is correct — there is no execve to intercept — but it means an attacker who never calls execve (e.g., `command="while true; do : ; done"`) is not constrained by the guard. The guard is exec-only by design; that is a pre-existing F4-adjacent property, not new in Sprint 6B.

### 6.5 HTTP attack vectors (request smuggling, header injection)

Not probed live this audit. The action server is FastAPI on `127.0.0.1:30000` with `urllib`/playwright clients. FastAPI's request parsing rejects the typical CL-CL-and-TE smuggling shapes; uvicorn is the underlying ASGI server. No new finding from cursory inspection. A Sprint 7 fuzzing pass against `/execute_action` would be reasonable hygiene, but the guard's threat model is execve interception — even if the action server itself were exploited via HTTP, an attacker would still need to reach execve to gain code execution outside Python, and that path is supervised.

### 6.6 No new guard source — does Sprint 6B unprove anything?

No. Because the guard is unchanged, no Sprint 2/4 invariant can have regressed inside the guard binary. Sprint 6B's contribution is purely: **the existing guard binary, when invoked as the parent of the OpenHands action server inside the pinned runtime image, supervises the agent-runtime command path end to end.** That is a meaningful and accurate architectural claim.

---

## 7. F4 Deferral and OpenHands Web-App / LLM-Agent Handoff State

**F4 carry-forward.** Verified present (Section 3 above): three independent disclosures across gate, proof body, and "Claims Still Not Allowed."

**OpenHands handoff state.** The proof memo's "Claims Still Not Allowed" (lines 165–172) lists:
- "Full OpenHands web app integration."
- "A claim that an LLM autonomously generated the blocked action."
- "A claim that F4 is fixed."
- "A production-grade sandbox claim."
- "Complete filesystem, network, or data-exfiltration isolation."
- "A minimal or universal policy for all OpenHands workflows."
- "A claim that the mounted source-tree shape exactly matches every deployed OpenHands runtime configuration."

This is honest. The "mounted source-tree shape" caveat is particularly worth flagging: this run mounts `external/OpenHands-1.6.0` read-only at `/openhands/code` and sets `PYTHONPATH=/openhands/code` because the runtime image alone does not import `openhands` cleanly without source. A production OpenHands deployment may bake the source into a different layer; the integration boundary is not yet proven against every deployed shape. The proof memo names this in "Notes" (lines 178–181). Honest.

What's still missing for a fuller demo:
1. **LLM-agent loop**: a real OpenHands controller calling `/execute_action` as a result of LLM reasoning, not a hard-coded harness script.
2. **Non-execve action coverage**: FileWrite/FileRead/FileEdit constrained.
3. **Policy file integrity**: Landlock WRITE-deny on the policy path so a FileWriteAction cannot rewrite the allowlist.
4. **Production deployment topology**: not bind-mounting the OpenHands source from outside the image; using the image as built.

None of these are pre-registered as a Sprint 7 gate yet.

---

## 8. Sprint 7 Prerequisites

In approximate priority order:

1. **Pre-register Sprint 7 gate as a separate commit before any Sprint 7 work.** The Sprint 6 streak (`fe5bd19` → `78a2ba1`, `c4392ae` → `243068f`) has now established the discipline twice. Keep it.

2. **Decide whether Sprint 7 is (i) LLM-agent-issued, (ii) non-execve coverage, or (iii) production deployment topology — and do exactly one.** Three valuable directions, but conflating them in one sprint reproduces the Sprint 5/6 confusion the discipline finally fixed.

3. **If Sprint 7 = LLM-agent**: a small controller that hits `/execute_action` via the OpenHands controller's normal code path, with a recorded LLM prompt → action sequence preserved as evidence. Use a small, deterministic model or a recorded cassette so the proof is reproducible offline.

4. **If Sprint 7 = non-execve coverage**: extend the guard with Landlock READ/WRITE rules over the policy directory and (optionally) a denylist over `/openhands/code` and `/lab/bin/`; demonstrate that a `FileWriteAction` cannot rewrite the allowlist and that the next `/execute_action` still uses the pre-registered policy.

5. **If Sprint 7 = production topology**: do not bind-mount external source. Use the runtime image as built, possibly with a small Dockerfile overlay that places the guard binary and policy in the image rather than from a bind mount. Demonstrate that the guarded action-server boots from image-resident code.

6. **F4 architecture work remains the standing carry-forward.** Not gated on Sprint 7.

7. **Add `/execute_action` HTTP fuzz harness** as a low-priority hygiene item: cheap to write, would surface request-smuggling/header-injection issues if any.

### What distinguishes "ready to demo" from "ready to ship"

- **Ready to demo (today, after Sprint 6B):** Show the harness running end-to-end; explain that the guard sits in front of the action server's command path; show the BLOCK record. The audience-appropriate caveat is the "Claims Still Not Allowed" list, named honestly.
- **Ready to ship (not today):** All four of {LLM-agent integration, non-execve coverage including policy-file integrity, production topology that doesn't depend on bind-mounted source, OpenHands web-app surface decision (in or out of scope)} need to be settled. Plus F4 architecturally (or an explicit decision that F4 stays deferred for the shipping product, with a documented compensating control).

---

## 9. Honest Headline

**The current claim is accurate.** The proof memo's `## Claim Now Allowed` paragraph (lines 161–162):

> "A local seccomp user-notify plus Landlock execution guard can wrap the pinned OpenHands `action_execution_server.py` runtime path, supervise real `/execute_action` `CmdRunAction` commands through `BashSession`, allow an approved workspace file read, block a copied and renamed `/usr/bin/rm` before output, and preserve parseable guard audit JSON under Docker default seccomp."

I would not tighten this further; the operator has already pre-tightened it. One sentence I would *add* to the proof memo for full discipline (mirroring my Sprint 5 recommendation):

> "Note: the `/execute_action` HTTP request was issued by a hard-coded harness client (`send_action.py`), not by an OpenHands LLM-agent loop. Sprint 6B proves the agent-runtime command path is supervised; it does not yet prove that an autonomous LLM-issued action is supervised. Sprint 7 should pre-register the LLM-agent path."

That single addition closes the strongest narrowing this audit found.

---

## 10. Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

git log --oneline -15
git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_GATE_20260501.md
git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_ACTION_SERVER_PROOF_20260501.md
git status --short

sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
          policy/integration/openhands_action_server.allow.json \
          scripts/integration/replay_sprint6b_action_server.sh \
          proofs/SPRINT6B_GATE_20260501.md

git show 78a2ba1:bin/usernotify_exec_guard | sha256sum
git show 78a2ba1:guard/usernotify_exec_guard.c | sha256sum

bash scripts/integration/replay_sprint6b_action_server.sh
   → pass=12 fail=0
   → run_root=…/sprint6b-action-server-20260501T005827Z

bash scripts/replay_sprint2_identity.sh                          → pass=12 fail=0
bash scripts/replay_sprint4_audit_integrity.sh                   → pass=22 fail=0
bash scripts/integration/replay_sprint5_docker_guard.sh          → pass=11 fail=0
bash scripts/integration/replay_sprint6_openhands_runtime.sh     → pass=13 fail=0

# audit log post-mortem on the operator's final run:
grep '"event":"exec_decision"' \
   proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/container_logs.combined \
 | python3 -c '<categorize ALLOW/BLOCK + workspace cwd>'
   → 84 ALLOW (tmux/bash/cat/cp/chmod/which/...)
   → 5 BLOCK (./python3 in workspace + 4 unresolved /openhands/.../git lookups)

cat proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/action_allowed_cat.response.json
cat proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/action_block_renamed_rm.response.json

# OpenHands source inspection at pinned tag c5e0de8e:
grep -nE '@app\.(get|post|put|delete)' external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py
grep -n "tmux\|libtmux\|Popen\|subprocess" external/OpenHands-1.6.0/openhands/runtime/utils/bash.py
grep -n "session_api_key\|SESSION_API_KEY\|verify_api_key" external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py

# guard's Landlock surface check:
grep -n "LANDLOCK_ACCESS" guard/usernotify_exec_guard.c
   → only LANDLOCK_ACCESS_FS_EXECUTE; no WRITE/READ rules

# /tmp scope:
ls /tmp/*sprint6* /tmp/*aeg* /tmp/*action_server* /tmp/*openhands* 2>/dev/null
   → none from Sprint 6B
```

No retained `/tmp` artifacts created by this audit. The Sprint 6B harness writes only inside `proofs/sprint6b_runs/<run-id>/`, and the in-container scratch lives inside the `--rm`-able container (already cleaned by the harness's `cleanup_container`).

---

## 11. Files

- This audit: `proofs/AUDIT_20260501_sprint6b_independent_review_a.md`
- Pre-registered gate: `proofs/SPRINT6B_GATE_20260501.md` (commit `c4392ae`, 2026-04-30 17:39:02 -0700)
- Proof memo: `proofs/SPRINT6B_ACTION_SERVER_PROOF_20260501.md` (commit `243068f`, 2026-04-30 17:54:54 -0700)
- Command log: `proofs/SPRINT6B_COMMAND_LOG_20260501.md`
- Final operator run: `proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/`
- Auditor reproduction runs: `proofs/sprint6b_runs/sprint6b-action-server-20260501T005827Z/` (and `…005856Z`)
- Replay harness: `scripts/integration/replay_sprint6b_action_server.sh`
- Policy: `policy/integration/openhands_action_server.allow.json`
- OpenHands source under inspection: `external/OpenHands-1.6.0/` at commit `c5e0de8ecd85cef10e7808d57e9f939f3770ab9d` (tag 1.6.0)
- Guard source: `guard/usernotify_exec_guard.c` (sha256 `07a27fd1…`, unchanged from Sprint 6A)
- Guard binary: `bin/usernotify_exec_guard` (sha256 `e3bdaabf…`, unchanged from Sprint 6A)
