# Sprint 6B — Independent Audit Review (Auditor B)

Date: 2026-05-01
Auditor: Auditor B (independent adversarial pass on Sprint 6B self-claim `SPRINT6B_ACTION_SERVER_PROOF_20260501.md`).
Posture: re-derive provenance, re-run the Sprint 6B harness live, decide whether the action-server `/execute_action` proof actually closes the (a)→(b) gap that Sprint 5's Auditors A and B both named, audit the new HTTP attack surface introduced by reaching across `/execute_action`, and re-test Sprint 2 / Sprint 4 / Sprint 5 / Sprint 6A invariants live.

A parallel Auditor A is running the same brief independently. I did not coordinate.

---

## 1. Audit Question

Does Sprint 6B prove that the seccomp user-notify + Landlock guard actually wraps the OpenHands runtime command-execution path — `action_execution_server.py`'s `/execute_action` endpoint — such that any `CmdRunAction` issued through that endpoint is intercepted by the guard, with prior regressions intact, F4 still disclosed, and the gate honestly pre-registered ahead of the proof?

## 2. Verdict

**Sprint 6B is real interpretation (b), within the narrow scope of `CmdRunAction` execution through the action server's `/execute_action` HTTP endpoint backed by the action server's `BashSession` (libtmux + bash) command path. The guard demonstrably supervises every `execve` in the entire process tree from `micromamba` → `poetry` → `python` → action_server → `tmux` → `bash` → `cat` (and the blocked copied `./python3`). The (b) interpretation that Sprint 5 Auditors A and B both named as gating is closed for this surface. Pre-registration is now correct on the git timeline (gate at `c4392ae` 17:39 PDT; proof at `243068f` 17:54 PDT, 15 minutes later). All four prior regressions reproduce green live: Sprint 2 (12/0), Sprint 4 (22/0), Sprint 5 (11/0), Sprint 6A (13/0). The Sprint 6B headline is accurate.**

The discipline-level findings are below — none of them invalidate the Sprint 6B claim, and none of them are "Sprint 6B is overstated":

- The action server has at least four non-execve action types — `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, `BrowseURLAction` — plus several non-`/execute_action` HTTP endpoints (`/upload_file`, `/download_files`, `/list_files`, `/update_mcp_server`). Sprint 6B's harness disables the Jupyter and browser plugins on the command line and exercises only `/execute_action` with `CmdRunAction`. The proof memo correctly says "action-server command-path integration proof. It is stronger than Sprint 6A and still narrower than a full OpenHands app or autonomous-agent proof." That sentence does carry the load. But a strict reader could conclude the (b) claim should explicitly say "(b) for the `cmd_run` command-execution path; (b') for the file/IPython/browse/MCP/upload paths is not yet proven."
- The guard binary is **unchanged** from Sprint 4 / Sprint 5 / Sprint 6A: `e3bdaabfc1b9b9404482ad80c6c2d6dccb0efe76046ec390223eae21abdcba5b`. Sprint 6B is purely scripts + policy + docs. This is the right design (no surface change required; integration is configuration), but the headline "guard wraps the action server" should not be read as "the guard learned anything new about HTTP." It learned a new wrapper invocation context.
- Two stopped exploratory containers remain in the local Docker daemon (`aeg-s6b-action-server`, `aeg-s6b-action-server-src`) from earlier experimentation runs. These are Docker resource leftovers, not host `/tmp` artifacts. The Sprint 6B harness cleans up the *named container it owns*; it does not garbage-collect earlier exploratory names. Cosmetic, not blocking.

The honest one-line summary of Sprint 6B's actual state:

> "The pinned `ghcr.io/openhands/runtime:1.6.0-nikolaik` action_execution_server.py at OpenHands tag 1.6.0 commit `c5e0de8`, started under the local seccomp+Landlock guard with policy `sprint6b_openhands_action_server_allowlist_v1`, served a real HTTP POST `/execute_action` request with `CmdRunAction(command='cat input.txt')` through `BashSession` and the request returned `success=true exit_code=0 content=sprint6b-action-server-file`. A second `/execute_action` with `cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version` was blocked by the guard at `execve` time (`reason=blocked_executable_identity`, `raw_exe=./python3`, sha256 of the copied binary recorded), and the action server returned `success=false exit_code=126 content=bash: ./python3: Operation not permitted`. The guard audit stream captured 89 ALLOW/BLOCK exec_decision records across the entire process tree (micromamba, poetry, python, tmux, bash, cat, …). The proof is interpretation (b) for the `CmdRunAction` path; non-execve action paths (file read/write, IPython, browse) are not exercised."

Recommend: **Sprint 6B is kept**. Sprint 7 should generalize the proof to `FileWriteAction`+`CmdRunAction` chained, or to a real LLM-driven action sequence.

---

## 3. Discipline Check — Was the Gate Pre-Registered? Was Carry-Forward Open Items Present?

### 3.1 Pre-registration

Sprint 6B finally lands the gate-then-proof split that Sprint 5 Auditors A, B, and the follow-up auditor all named as the forward-looking discipline change.

```
$ git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_GATE_20260501.md
c4392ae 2026-04-30 17:39:02 -0700 Pre-register Sprint 6B OpenHands command path gate

$ git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_ACTION_SERVER_PROOF_20260501.md
243068f 2026-04-30 17:54:54 -0700 Sprint 6B OpenHands action server proof
```

The gate landed in its own commit at 17:39, the proof in a separate commit 15:52 minutes later at 17:54. Git history alone now distinguishes gate from proof. **This is the discipline win the prior sprint audit asked for. Closed.**

(Sprint 6A's gate-then-proof split was the first to use this pattern: `fe5bd19` gate then `78a2ba1` proof. Sprint 6B preserves the discipline. Two consecutive sprints of correct gate-first commits is enough to call this a stable practice rather than a one-off.)

### 3.2 Carry-Forward Open Items

The gate's table has 16 rows: F1, F2, F3, F4, F5, F6, F7, F8, A1, A2, A3, A4, B5, B6, Sprint 6A, Production-grade sandbox. The proof memo's table has 17 rows: same items plus a "Full OpenHands app / LLM-agent proof — not claimed" row. Both inherit and re-stamp the full Sprint 4 / Sprint 5 / Sprint 6A enumeration. F4 is named explicitly ("Deferred and disclosed; not fixed by Sprint 6B") in both gate and proof. **Closed.**

---

## 4. The (a) vs (b) Determination With Evidence — Headline Finding

This is the load-bearing question for Sprint 6B. Sprint 5 ended in interpretation (a) with both Auditors A and B explicitly naming "agent-in-container-supervised-by-guard" as the next gate. Sprint 6A landed (a) again — guard-in-the-pinned-OpenHands-runtime-image — and explicitly disclaimed (b). The promise of Sprint 6B was (b).

**Sprint 6B delivers (b) for the `CmdRunAction` command path.** Evidence:

1. **The replay script issues a real HTTP POST to the action server's `/execute_action` endpoint.** It is not a synthetic in-process call. From `scripts/integration/replay_sprint6b_action_server.sh:160-167`:

    ```python
    req = urllib.request.Request(
        "http://127.0.0.1:30000/execute_action",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        sys.stdout.write(resp.read().decode())
    ```

    The payload is a serialized `CmdRunAction`:

    ```json
    {"action": {"action": "run", "args": {"command": "cat input.txt", "is_input": false, "blocking": false, "is_static": false}}}
    ```

    This is the same envelope an OpenHands controller would send.

2. **The action server is started under the guard.** `replay_sprint6b_action_server.sh:94-106`:

    ```
    docker run -d --name aeg-... \
      -v $ROOT:/lab:rw \
      ghcr.io/openhands/runtime:1.6.0-nikolaik \
      /lab/bin/usernotify_exec_guard \
      --policy /lab/policy/integration/openhands_action_server.allow.json \
      /openhands/micromamba/bin/micromamba run -n openhands \
      poetry run python -u -m openhands.runtime.action_execution_server 30000 \
      --working-dir <workspace> --username daemon --user-id 1 --no-enable-browser
    ```

    The guard is **the container's pid 1**. The action server is a descendant. The seccomp filter installed by the guard is inherited across `clone()` to every descendant in the process tree — that is the kernel's seccomp inheritance contract.

3. **Every `execve` in the entire descendant tree is supervised.** I parsed `proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/container_logs.combined`:

    ```
    exec_decision events: 89  (ALLOW=84, BLOCK=5)
    distinct raw_exe values: 22, including:
      /openhands/micromamba/bin/micromamba
      /openhands/micromamba/envs/openhands/bin/poetry
      /openhands/poetry/openhands-ai-.../bin/python
      /usr/bin/tmux
      /usr/bin/bash
      /usr/bin/cat
      /usr/bin/cp, /usr/bin/chmod, /usr/bin/chown, /usr/bin/id, /usr/bin/mkdir, /usr/bin/which
      ./python3                ← the blocked copied rm
    ```

    The interesting two:

    - **The allowed `cat input.txt` is recorded as a guard ALLOW** with `pid=220`, `raw_exe=/usr/bin/cat`, `argv=["cat","input.txt"]`, `cwd=.../workspace`, sha256 of `/usr/bin/cat`, all the standard fields. This is the literal `execve` triggered by the `BashSession`'s `tmux send_keys "cat input.txt"` → tmux server → bash → execve(cat). It is end-to-end:

        ```
        HTTP /execute_action POST → action_server.run_action(CmdRunAction)
          → BashSession.execute → libtmux pane.send_keys("cat input.txt")
          → tmux server (already running, supervised) → bash (already running, supervised)
          → bash forks and execve("/usr/bin/cat", ["cat","input.txt"]) ← GUARD INTERCEPTED HERE
        → bash captures stdout → tmux pane buffer → BashSession reads → CmdOutputObservation
        → JSON response → HTTP 200
        ```

    - **The blocked `./python3` is recorded as a guard BLOCK** with `decision=BLOCK`, `reason=blocked_executable_identity`, `raw_exe=./python3`, `realpath=/lab/proofs/.../workspace/python3`, `sha256=c761a9dffe245730...` (the hash of the copy of `/usr/bin/rm`), `argv=["./python3","--version"]`. The action server's HTTP response carries `success=false exit_code=126 content=bash: ./python3: Operation not permitted`. So the block is observable both in the guard's audit log and in the HTTP response payload.

4. **The supervised process tree includes long-lived processes.** Both `tmux` and `bash` show up as ALLOW exec_decisions early in the run (during BashSession `__init__`), and then later command execve's (`cat`, the blocked `./python3`) appear as descendants of that long-lived bash. This proves the guard's seccomp filter is inherited by the long-lived bash, not just by short-lived spawn-and-exit children — i.e., interpretation (b) is the actual process-model claim, not (c) "guard wraps the entrypoint but commands fired by the agent might escape."

5. **Audit JSON parses end-to-end** (`pass=container_logs_json`). I re-validated by counting `{"event":"exec_decision"` lines and parsing each one with Python — 89/89 parse cleanly.

**Determination:** Sprint 6B is real (b) for the `CmdRunAction` command-execution path. The (c) "intermediate" interpretation — "guard wraps action server entrypoint but commands fired by the agent through the action server might bypass the guard" — is **affirmatively ruled out** by evidence: the guard's seccomp filter survives the BashSession-establishing tmux/bash fork, and downstream agent-issued `execve` calls (e.g., `cat`, `cp`, `chmod`, `./python3`) all show up as exec_decision records.

This is the first sprint that legitimately closes the (a)→(b) gap that Sprint 5 Auditor A, Auditor B, and the Sprint 5 follow-up auditor all named as gating.

---

## 5. What Verified Clean Independently

### 5.1 SHAs match the proof memo

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

All five SHAs match the values claimed in the proof memo and command log. The guard binary `e3bdaabf...` is **identical** to the binary used since Sprint 4. Sprint 6B is purely scripts/policy/docs work — no source or binary surface change.

### 5.2 Live re-run of Sprint 6B replay

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
run_root=/home/blazingradar/agent-exec-guard-lab/proofs/sprint6b_runs/sprint6b-action-server-20260501T005856Z
```

12/12 reproduces live on this host. The image identity in my run dir matches the gate's pinned digest `sha256:cd7816c0780dd59009372361c0f5ee61cdf0e0057c6696d681a4330766c62e60`. The `HostConfig.SecurityOpt=None` evidence is preserved (Docker default seccomp profile is in effect; no `--security-opt seccomp=unconfined` override).

### 5.3 Live re-run of all four prior regressions

```
Sprint 2 identity replay (sprint2-20260501T005916Z):                     pass=12 fail=0
Sprint 4 audit integrity replay (sprint4-20260501T005917Z):              pass=22 fail=0
Sprint 5 Docker container replay (sprint5-docker-20260501T005920Z):      pass=11 fail=0
Sprint 6A OpenHands runtime replay (sprint6-openhands-runtime-20260501T005922Z): pass=13 fail=0
```

All four reproduce green live. F1/F2/F3/F5/F6/F7/F8 + A1/A2/A3/A4 + B5/B6 closures still hold under the unchanged `e3bdaabf...` binary.

### 5.4 Docker access posture

`docker ps` from the auditor's primary login fails: `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`. The `sg docker -c "..."` group-substitution workaround works — same posture as Sprint 1's baseline and Sprint 5/6A. Sprint 6B's harness uses `sg docker -c` consistently, matching prior sprints. No new Docker access regression.

### 5.5 Action server HTTP behavior is real

I confirmed by reading:

- `proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/alive_probe.stdout`:
  `200 {"status":"ok"}`
- `action_allowed_cat.response.json`:
  ```
  {"message":"Command `cat input.txt` executed with exit code 0.", "observation":"run",
   "content":"sprint6b-action-server-file", ..., "success":true}
  ```
- `action_block_renamed_rm.response.json`:
  ```
  {"message":"Command `cp /usr/bin/rm ./python3 && chmod +x ./python3 && ./python3 --version` executed with exit code 126.",
   "observation":"run", "content":"bash: ./python3: Operation not permitted", ..., "success":false}
  ```

Both responses are well-formed `CmdOutputObservation` payloads that an OpenHands controller could consume. The action server is **really running**, not stubbed. Hostname `0d0f8e247a60` matches the container ID in `docker_run.stdout`.

### 5.6 Guard audit stream cross-check

`grep '{"event":"exec_decision"' container_logs.combined | wc -l` → 89 records. ALLOW=84, BLOCK=5. The 5 BLOCKs:

1. `/openhands/poetry/openhands-ai-.../bin/git` — git not at this path (`unresolved_executable_identity`)
2. `/openhands/micromamba/envs/openhands/bin/git` — same
3. `/openhands/micromamba/condabin/git` — same
4. `/openhands/bin/git` — same
5. `./python3` — the copied `rm` (`blocked_executable_identity`)

Items 1-4 are PATH-walk misses by `which git` during BashSession startup; the guard treats "policy lists git but this realpath isn't in the allowlist" as `unresolved_executable_identity`. Eventually `/usr/bin/git` is found and ALLOW'd. The pattern is consistent with previous sprints.

The blocked `./python3` record carries the SHA256 of the copy (`c761a9dffe245730ee7a579bcf49006f8d94c98f55f6293283a566f903b6fc4a`), the device/inode pair, the cwd, and a complete argv envelope. F7 (argv truncation metadata) and A2 (argv count cap) markers are present, confirming the Sprint 4 audit-integrity invariants survive into Sprint 6B's record.

### 5.7 Claim vs evidence cross-walk for the 12 PASS records

| PASS record | Required artifact | Present? |
|---|---|---|
| source_commit c5e0de8ecd85cef10e7808d57e9f939f3770ab9d | `source_commit.txt` | yes (one line, exact) |
| image_identity recorded | `image_identity.txt` (image inspect) | yes (digest + size) |
| docker_run container started | `docker_run.stdout` (container ID), `docker_run.exit_code` | yes (`0`, ID `0d0f8e247a60...`) |
| docker_inspect recorded | `docker_inspect.json` (9.7 KB) | yes |
| docker_securityopt_default HostConfig.SecurityOpt=None | `hostconfig_securityopt.txt` | yes (`None`) |
| alive_probe server returned /alive | `alive_probe.stdout` (`200 {"status":"ok"}`) | yes |
| action_allowed_cat HTTP action returned | `action_allowed_cat.response.json`, exit_code=0 | yes |
| action_allowed_cat_result workspace file read via /execute_action | response: `success=true`, `exit_code=0`, `content=sprint6b-action-server-file` | yes |
| action_block_renamed_rm HTTP action returned | `action_block_renamed_rm.response.json`, exit_code=0 | yes |
| action_block_renamed_rm_result renamed rm blocked via /execute_action | response: `success=false`, `exit_code=126`, `Operation not permitted` | yes |
| container_logs_json guard audit lines parse | `container_logs.combined` (89 JSON lines) | yes |
| guard_log_blocked_python3 guard logged copied rm block | grep for `"reason":"blocked_executable_identity".*"raw_exe":"./python3"` matches one line | yes |

All 12 PASS records have explicit, parseable backing artifacts. No PASS is asserted without underlying evidence.

---

## 6. New Findings or Attack Surfaces Specific to Sprint 6B

These are surfaces that did not exist as concerns in Sprints 2–6A because earlier sprints did not reach across an HTTP API. They are not regressions; they are scope-of-claim observations a strict reader might want stated.

### S6B-1 Non-execve action types are not exercised

The action server has at least four non-`CmdRunAction` action paths reachable through `/execute_action`:

```
external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py:
  line 406  async def run_ipython(self, action: IPythonRunCellAction)
  line 449  async def read(self, action: FileReadAction)
  line 518  async def write(self, action: FileWriteAction)
  line 598  async def browse(self, action: BrowseURLAction)
  line 606  async def browse_interactive(self, action: BrowseInteractiveAction)
```

None of these go through `execve` for the actual data movement: `read` uses Python `open()` directly (line 502); `write` uses `open(..., 'w')`; `run_ipython` injects code into a Jupyter kernel running in the same Python interpreter or a sibling process (already supervised by the guard for its `execve`'s, but not for in-kernel `os.system`-style code execution); `browse*` drives a Playwright/browser process. **The guard's seccomp filter only intercepts `execve` and `execveat`. It does not intercept `open`, `read`, `write`, `mmap`, or arbitrary in-process Python.**

In Sprint 6B's specific harness:

- The Jupyter plugin is **not loaded** because the harness command line does not pass `--plugins jupyter`. So `run_ipython` cannot be called — it would return an `ErrorObservation('jupyter plugin not loaded')`.
- The browser is disabled by `--no-enable-browser`.
- `read` and `write` are **always available**. They are not exercised by Sprint 6B.

**Attack the Sprint 6B harness can not catch today (without further policy + scripts work):**

1. An attacker who can reach `/execute_action` could send `FileWriteAction(path='/tmp/evil', content=<malicious binary bytes>)`. The Python `open(...).write(...)` is not intercepted. Then `CmdRunAction(command='chmod +x /tmp/evil && /tmp/evil')` would be intercepted by the guard at execve — and the policy would BLOCK because `/tmp/evil` is not in the allowlist. So the guard catches this **at execution time** via Sprint 2's identity property. This is the same defense pattern Sprint 2's "copied `/usr/bin/rm` renamed as `python3`" demonstrated, generalized one layer up.

2. An attacker could send `FileReadAction(path='/etc/shadow')`. There is no host `/etc/shadow` mounted (the workspace is `/lab:rw` and the OpenHands source is `/openhands/code:ro`), but the container's own `/etc/shadow` exists and is reachable from inside. The guard does not see this — it is plain `open()`. **This is a real read-side gap not covered by Sprint 6B's claim.** The Sprint 6B claim is "command-execution path is supervised," and that is honest; it is not "data-exfil path is supervised."

3. `/upload_file`, `/download_files`, `/list_files`, `/update_mcp_server` are HTTP endpoints other than `/execute_action`. `/update_mcp_server` is particularly interesting: it could mount an MCP proxy that becomes a new command-issuing surface. Sprint 6B does not cover these.

**Recommendation:** The Sprint 6B headline ("guard wraps OpenHands' command-execution path") is honest because `/execute_action` + `CmdRunAction` *is* OpenHands' command-execution path. But the proof memo's "Claim Now Allowed" sentence should explicitly enumerate "for the `CmdRunAction` flow" rather than imply blanket coverage of the action server's whole HTTP surface. Concretely, the existing sentence:

> "A local seccomp user-notify plus Landlock execution guard can wrap the pinned OpenHands `action_execution_server.py` runtime path, supervise real `/execute_action` `CmdRunAction` commands through `BashSession`, allow an approved workspace file read, block a copied and renamed `/usr/bin/rm` before output, …"

does say "real `/execute_action` `CmdRunAction` commands" — it is technically tight. So this is "honestly worded; could be louder about the scope," not "overstated."

### S6B-2 HTTP attack surface against the action server

The action server is `uvicorn` on port 30000. The harness drives it from `urllib.request`. Encoding tricks (oversized payloads, malformed JSON, `Content-Type` smuggling, header injection, HTTP/2 request smuggling) are not exercised. These would attack the *action server*, not the *guard*. If the action server crashes on a malformed request, the guard would record the action server's death and the container would exit. That is honest fail-closed behavior, not a guard bypass.

The thing a reviewer should explicitly *not* claim is that the guard hardens the action server against HTTP attack. It hardens what the action server can `execve`, nothing more.

### S6B-3 Race conditions in the BashSession process model

`BashSession.execute()` uses `tmux send_keys` on a persistent pane. If two `/execute_action` requests arrive quickly, libtmux's pane is single-threaded and they queue at the action server. The guard's seccomp filter is per-process and inherited across forks; race conditions between the supervisor accepting a notification and the child being scheduled are the F4 territory (TOCTOU). F4 is explicitly disclosed and deferred. Sprint 6B introduces a long-lived bash that issues many `execve`'s over time, which is a richer F4 attack surface than Sprint 2's short-lived spawn-and-exit pattern. **F4 disclosure should be considered more prominent post-Sprint-6B**, even though F4 itself is unchanged.

### S6B-4 Workspace mount semantics

The harness mounts `$ROOT:/lab:rw` (read-write) and `$SOURCE_DIR:/openhands/code:ro`. The action server's workspace is at `/lab/proofs/sprint6b_runs/$RUN_ID/workspace`. Any malicious binary the agent writes to that workspace is on a real bind-mounted host directory — meaning it persists on the host filesystem after container removal, owned by the in-container user (in this case `daemon`). After my own re-runs I verified the workspace dir on the host is owned `daemon:root`, has mode 755, and contains only `input.txt` and (in some prior runs) `python3` (the copy of rm) — all benign. But strict reviewers would want an explicit cleanup-on-success step that removes the bind-mounted workspace after the test passes, since `python3` (a 76-byte copy of rm with the rm-binary semantics) is a small artifact left on the host. (It is owned by `daemon`, which is a non-root user, so the blast radius is small.)

### S6B-5 Two stopped exploratory containers remain

```
$ sg docker -c 'docker ps -a' | grep aeg-
bea253e38b92  ...nikolaik  /lab/bin/usernotify…  19 minutes ago  Exited (1)  aeg-s6b-action-server-src
6050561485dc  ...nikolaik  /lab/bin/usernotify…  19 minutes ago  Exited (1)  aeg-s6b-action-server
```

These are leftover stopped containers from earlier exploratory runs (under different names than the Sprint 6B harness uses). The Sprint 6B harness cleans up the *named container it owns* (`aeg-${RUN_ID}`) at the end of each run. These two are pre-existing exploratory artifacts. Cosmetic, not blocking. A house-cleaning `docker rm -f aeg-s6b-action-server aeg-s6b-action-server-src` would tidy this up.

---

## 7. F4 Deferral and OpenHands Web-App / LLM-Agent Handoff State

### 7.1 F4

The proof memo's Carry-Forward table line for F4 reads:

> "F4 `SECCOMP_USER_NOTIF_FLAG_CONTINUE` TOCTOU — Deferred and disclosed; not fixed by Sprint 6B"

Body text repeats: "A claim that F4 is fixed" is in the "Claims Still Not Allowed" list. Discipline is correct.

I noted in S6B-3 that Sprint 6B materially expands the F4 attack window in *practice* by introducing a long-lived bash inside the supervised tree. A future audit pass should consider whether F4's disclosure needs richer narrative than "Deferred" — e.g., a sentence saying "F4 is unchanged in scope but more attackable in this configuration than in Sprint 2's short-lived spawn pattern." This is not Sprint 6B's blocker; it's a Sprint 7 or post-Sprint-6B disclosure-tightening item.

### 7.2 OpenHands web-app / LLM-agent handoff

The proof memo's "Claims Still Not Allowed" list is explicit:

- "Full OpenHands web app integration"
- "A claim that an LLM autonomously generated the blocked action"

And the "Notes" section ends with: "The Sprint 6B proof is therefore an action-server command-path integration proof. It is stronger than Sprint 6A and still narrower than a full OpenHands app or autonomous-agent proof."

The boundary statement requested in the audit brief is **honestly stated** in both the carry-forward row ("Full OpenHands app / LLM-agent proof — Not claimed in Sprint 6B") and the closing notes. **Closed.**

What is still missing for a full demo:

1. An LLM agent (or recorded LLM trace) actually issues the `CmdRunAction` payload, rather than the harness directly issuing it.
2. The non-`CmdRunAction` action types (`FileWriteAction`, `IPythonRunCellAction`, `BrowseURLAction`) either (a) are exercised against the guard, or (b) are explicitly out of scope for production use, or (c) are wrapped at a higher layer (e.g., write-side Landlock or a non-execve audit hook).
3. The OpenHands "controller" half of the architecture — the part that issues actions to the action server — has not been integrated. Sprint 6B is the runtime side only.

---

## 8. Sprint 7 Prerequisites — Or What Distinguishes "Ready to Demo" From "Ready to Ship"

### 8.1 Sprint 7 is not pre-registered yet

`ls proofs/SPRINT7_*` returns nothing. There is no Sprint 7 gate file on disk or in the git history yet. So Sprint 6B is the natural stopping point for the current arc.

### 8.2 What "ready to demo" means today

After Sprint 6B, the lab can demonstrate:

- A pinned OpenHands runtime container.
- Started under a local seccomp+Landlock guard.
- Receiving a real HTTP `CmdRunAction` POST.
- Allowing approved commands.
- Blocking copied/renamed non-policy executables on identity (the Sprint 2 invariant generalized through the action server).
- With a parseable JSON audit stream (Sprint 4 invariant).
- Under Docker's default seccomp profile (Sprint 5 invariant).

That is a credible technical demo of "guard supervises OpenHands' command path." For a 5-minute demo to a security audience, it's sufficient.

### 8.3 What "ready to ship" would still require

| Gap | Effort | Sprint 7 candidate? |
|---|---|---|
| Real LLM trace driving `/execute_action` (vs. harness-driven) | medium | yes — replay a captured agent trace |
| `FileWriteAction` + `CmdRunAction` chained attack scenario, end-to-end | small | yes — write malicious binary, exec it, verify guard blocks |
| `FileReadAction` data-exfil path covered (Landlock read deny on /etc, /root, etc.) | medium | yes — but this is policy + Landlock surface, not seccomp |
| `IPythonRunCellAction` + `BrowseURLAction` paths exercised, even if just to show the boundary | medium | yes — explicit "out of scope for cmd_run guard" disclosure |
| F4 fix (`SECCOMP_IOCTL_NOTIF_ADDFD + execveat`) | large | **no — explicitly deferred since Sprint 4** |
| Non-`/execute_action` HTTP endpoints covered (`/upload_file`, `/list_files`, `/update_mcp_server`) | medium | yes |
| OpenHands controller (server side) integration | large | yes — the other half |
| Production-grade sandboxing claim | very large | explicitly disclaimed since Sprint 1 |

The line between "ready to demo" and "ready to ship" is mostly: "shipping" requires the file/IPython/browse/MCP non-execve paths to either be covered or be explicitly documented as customer-side responsibility, plus the LLM-driven version of the proof.

A reasonable Sprint 7 gate would be: "Replay a real OpenHands LLM trace through the guarded action server, with at least one chained `FileWriteAction` → `CmdRunAction` attack attempt that the guard blocks at the execve boundary." That is a small, honest extension of Sprint 6B.

---

## 9. Honest Headline

**Current Sprint 6B headline is accurate.** I would not tighten it further than the proof memo already states.

The existing "Claim Now Allowed" sentence in the proof memo:

> "A local seccomp user-notify plus Landlock execution guard can wrap the pinned OpenHands `action_execution_server.py` runtime path, supervise real `/execute_action` `CmdRunAction` commands through `BashSession`, allow an approved workspace file read, block a copied and renamed `/usr/bin/rm` before output, and preserve parseable guard audit JSON under Docker default seccomp."

is technically tight. It says "real `/execute_action` `CmdRunAction` commands through `BashSession`" — those are exactly the surfaces tested. It does not over-claim coverage of `FileReadAction`, `FileWriteAction`, `IPythonRunCellAction`, or `BrowseURLAction`. It does not claim LLM autonomy.

If forced to suggest one tweak: append "; non-`CmdRunAction` action types and non-`/execute_action` HTTP endpoints are not yet covered" to make the scope louder for a casual reader. But this is a clarity improvement, not a correction.

The (a) vs (b) determination, plainly: **Sprint 6B is the first sprint that can honestly say it is interpretation (b), and it is the right narrowest version of (b).** Sprint 5 was (a). Sprint 6A was (a). Sprint 6B is (b) for the command path.

---

## 10. Commands Used For This Audit

```bash
cd /home/blazingradar/agent-exec-guard-lab
ls -la
ls proofs/ scripts/ scripts/integration/ proofs/sprint6b_runs/ proofs/sprint6_runs/ bin/ guard/

git log --oneline -20
git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_GATE_20260501.md
git log --diff-filter=A --pretty=format:'%h %ai %s' -- proofs/SPRINT6B_ACTION_SERVER_PROOF_20260501.md

# Read all proof artifacts
cat proofs/SPRINT6B_GATE_20260501.md
cat proofs/SPRINT6B_ACTION_SERVER_PROOF_20260501.md
cat proofs/SPRINT6B_COMMAND_LOG_20260501.md
cat scripts/integration/replay_sprint6b_action_server.sh
cat policy/integration/openhands_action_server.allow.json

# Verify final-run artifacts
ls -la proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/
cat proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/replay_summary.txt
cat proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/{action_allowed_cat,action_block_renamed_rm}.response.json
cat proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/{image_identity.txt,alive_probe.stdout,hostconfig_securityopt.txt,docker_run.stdout,source_commit.txt}

# Audit stream cross-check
wc -l proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/container_logs.combined
grep -c '"event":"exec_decision"' .../container_logs.combined
grep -c '"decision":"ALLOW"' .../container_logs.combined
grep -c '"decision":"BLOCK"' .../container_logs.combined
grep '"decision":"BLOCK"' .../container_logs.combined | python3 -c '...'
grep '"argv":\["cat","input.txt"\]' .../container_logs.combined
grep '"raw_exe":' .../container_logs.combined | python3 -c 'set unique raw_exe values'

# OpenHands source dispatch inspection
grep -n -E "def execute|tmux|popen|Popen|subprocess|execve|os\.system|run_command|BashSession" \
    external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py
grep -n -E "def execute|tmux|Popen|subprocess|execve|run_command|spawn|new_pane|send_keys" \
    external/OpenHands-1.6.0/openhands/runtime/utils/bash.py
sed -n '820,880p' external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py
grep -nE "/upload_file|/download_files|/list_files|@app\." \
    external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py
grep -rn -E "ipython|run_ipython|jupyter|kernel" \
    external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py

# Re-derive SHAs against the proof memo
sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard \
  policy/integration/openhands_action_server.allow.json \
  scripts/integration/replay_sprint6b_action_server.sh \
  proofs/SPRINT6B_GATE_20260501.md

# Live re-run of Sprint 6B
sg docker -c 'docker rm -f aeg-s6b-action-server-daemon >/dev/null 2>&1 || true'
bash scripts/integration/replay_sprint6b_action_server.sh

# Live re-run of all four prior regressions
bash scripts/replay_sprint2_identity.sh
bash scripts/replay_sprint4_audit_integrity.sh
bash scripts/integration/replay_sprint5_docker_guard.sh
bash scripts/integration/replay_sprint6_openhands_runtime.sh

# Docker access posture and leftovers
id; groups
docker ps    # fails (permission denied)
sg docker -c 'docker ps'
sg docker -c 'docker ps -a' | grep aeg-

# /tmp inspection
ls /tmp/ | grep -iE "openhands|aeg|sprint6b"
```

---

## Appendix — Where the (a)/(b) Evidence Lives

For a future auditor doing the same pass, the load-bearing artifacts are:

1. `scripts/integration/replay_sprint6b_action_server.sh` lines 137-168 (the real HTTP POST to `/execute_action`).
2. `scripts/integration/replay_sprint6b_action_server.sh` lines 92-106 (the action server is started under the guard binary as pid 1 of the container).
3. `proofs/sprint6b_runs/sprint6b-action-server-20260501T004956Z/container_logs.combined` lines containing `"argv":["cat","input.txt"]` (the agent-issued cat is intercepted at execve).
4. Same file: lines containing `"raw_exe":"./python3"` and `"reason":"blocked_executable_identity"` (the agent-issued copied rm is blocked).
5. Same file: lines containing `"raw_exe":"/usr/bin/tmux"` and `"raw_exe":"/usr/bin/bash"` (the long-lived BashSession's tmux+bash are themselves under the seccomp filter — proves filter inheritance survives the BashSession spawn).
6. `external/OpenHands-1.6.0/openhands/runtime/utils/bash.py` lines 230-250 (BashSession architecture: long-lived tmux session, persistent pane).
7. `external/OpenHands-1.6.0/openhands/runtime/action_execution_server.py` lines 820-840 (the `/execute_action` endpoint dispatch).

The combination proves: HTTP request from outside the container → action server in container → BashSession → tmux pane → bash → execve(cat) ← guard intercepts ← audit JSON record ← bash captures stdout ← tmux pane buffer ← BashSession reads ← CmdOutputObservation ← JSON HTTP 200 response. Every transition has an artifact backing it.
