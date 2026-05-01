# Sprint 5 — Follow-up Audit (commit 8332e93)

Date: 2026-04-30
Auditor: orchestrator (independent follow-up after Sprint 5's two orchestrator-spawned reviews + Bohr + Laplace subagent reviews).
Posture: verify whether commit `8332e93 Clean Sprint 5 proof metadata` actually closes the items the four prior auditors named.
Source of record: live commands run on this machine; commit history; preserved artifacts in proofs tree.

---

## Audit Question

The Sprint 5 audit chain (orchestrator A, orchestrator B, Bohr, Laplace) named six items. The candidate's follow-up commit `8332e93` claims to clean Sprint 5 proof metadata. Did it close the items, and did it introduce anything that should be flagged before Sprint 6?

## Verdict

**Five of six items closed. The remaining one is structurally unresolvable for Sprint 5 and is correctly addressed as a forward-looking discipline change for Sprint 6.**

The follow-up commit added two evidence directories (`proofs/sprint5_provenance/` and `proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/`), expanded the Carry-Forward Open Items table from 3 rows to 14, and replaced the prior `pass=6 fail=0` summary with `pass=11 fail=0` by explicitly counting checks the prior harness only failed on. No source or binary changes (`07a27fd1...` source, `e3bdaabf...` binary unchanged from Sprint 5 head). Working tree clean; commit pushed.

The honest one-line summary:

> "The Sprint 5 cleanup commit closes the four substantive items the prior auditors named: OpenHands 1.6.0 pin provenance is preserved as raw artifacts; the container's actual seccomp state is recorded as live evidence (`Seccomp: 2`, `HostConfig.SecurityOpt = null`); the harness now counts what it checks; and the Carry-Forward Open Items table now lists the full F1–F8 + A1–A4 + B5–B6 enumeration. The pre-registration timing concern (gate and proof co-staged in commit `e972a70`) is permanent in the Sprint 5 git history; it is correctly addressed by changing discipline going forward, not retroactively."

---

## Item-by-Item Status

| # | Auditor | Item | Status |
|---|---|---|---|
| 1 | orchestrator B | Carry-Forward Open Items section truncated to 3 rows | **CLOSED** |
| 2 | Bohr | No positive Docker runtime seccomp metadata recorded | **CLOSED** |
| 3 | Laplace medium 1 | OpenHands 1.6.0 pin provenance not retained | **CLOSED** |
| 4 | Laplace medium 2 | Docker default seccomp evidence inferential, not directly recorded | **CLOSED** |
| 5 | Laplace low 3 | Pass count under-represents what was checked | **CLOSED** |
| 6 | orchestrator A + B | Pre-registration by document framing, not git timeline | **STRUCTURALLY UNRESOLVED for Sprint 5** — forward-looking fix only |

---

## Verifications

### #1 — Carry-Forward Open Items expanded (orchestrator B finding)

`grep -nA 40 'Carry-Forward Open Items' proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md` shows the table now has 14 rows: F1, F2, F3, F4, F5, F6, F7, F8, A1, A2, A3, A4, B5, B6, plus a row for "OpenHands full runtime" and a row for "Production-grade sandboxing." Each row carries a status string (Closed / Deferred / Not allowed). This matches Sprint 4's full enumeration discipline. **Closed.**

### #2 — Container seccomp metadata (Bohr's finding)

`proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/proc_status.stdout`:

```
Seccomp:	2
NoNewPrivs:	0
```

`Seccomp: 2` = `SECCOMP_MODE_FILTER` is active inside the container at runtime. This is live evidence from `/proc/self/status` of a process inside the container.

`hostconfig_securityopt.txt`: `None` — confirms `HostConfig.SecurityOpt` is null, i.e., no `--security-opt seccomp=...` override was passed. Combined with `Seccomp: 2`, this is direct evidence that Docker's *default* seccomp profile (not a custom or unconfined one) was applied.

Note for the reader: `NoNewPrivs: 0` here is the right answer, not a regression. Docker doesn't set NNP for the container's pid 1 by default (containers run as root by default). The guard sets `PR_SET_NO_NEW_PRIVS` for *itself* before installing its seccomp filter; that's process-local and doesn't appear in this metadata snapshot, which was taken from a separate `docker create … /bin/sh -c 'grep ^Seccomp /proc/self/status; …'` — a process other than the guard. Sprint 6 should add a separate metadata record from inside the guard's child to capture NNP=1 there too, if it wants to make that property visible. **Closed for the original finding; one-line note for Sprint 6.**

### #3 — OpenHands pin provenance (Laplace medium 1)

`proofs/sprint5_provenance/` now contains 7 JSON artifacts plus `commands.txt` (the literal queries used) and `sha256s.txt` (SHA256 anchors for every file). The verbose runtime manifest reaches 34 KB and includes the platform-specific image digest list. A reviewer can verify the OpenHands 1.6.0 pin from preserved evidence without re-running external network queries. The `sha256s.txt` lines for the four `*.stderr` files all show `e3b0c44298fc...` — the empty-file SHA — which means every recorded query exited with no error output. **Closed.**

### #4 — Docker default seccomp directly recorded (Laplace medium 2)

Same `docker_metadata/` directory addressed in #2. Specifically:

- `docker_inspect.json` (7524 bytes) contains the full container inspect output.
- `hostconfig_securityopt.txt` extracts the `HostConfig.SecurityOpt` field as `None` (i.e., not overridden).
- `proc_status.stdout` records `Seccomp: 2` from inside the container.

Together these are direct evidence, not inference. **Closed.**

### #5 — Pass count expansion (Laplace low 3)

The new `proofs/sprint5_runs/sprint5-docker-20260501T002113Z/replay_summary.txt` shows:

```
PASS image_identity recorded
PASS docker_metadata_inspect HostConfig retained
PASS docker_securityopt_default HostConfig.SecurityOpt=None
PASS docker_proc_status_seccomp container reports Seccomp:2
PASS allowed_python exit=0 json=valid
PASS allowed_python_decision ALLOW decision recorded
PASS blocked_renamed_rm exit=126 json=valid
PASS blocked_renamed_rm_reason identity block recorded
PASS blocked_renamed_rm_output renamed rm did not execute
PASS stderr_forgery_contained exit=0 json=valid
PASS stderr_forgery_contained_check forgery captured as child_stderr
pass=11 fail=0
```

Compared to the prior Sprint 5 summary (`pass=6 fail=0`), this is +5 explicit pass records covering exactly the failure-only checks Laplace flagged: `allowed_python_decision`, `blocked_renamed_rm_reason`, plus three new docker-metadata pass records. The summary now represents what the harness actually verified. **Closed.**

### #6 — Pre-registration by document framing, not git timeline (orchestrator A + B)

`git log --diff-filter=A --pretty=format:'%H %ai' -- proofs/SPRINT5_GATE_20260430.md proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`:

```
e972a70af96938e82fee39b9acb0ce7eff2b47ef 2026-04-30 17:01:43 -0700  (gate)
e972a70af96938e82fee39b9acb0ce7eff2b47ef 2026-04-30 17:01:43 -0700  (proof)
```

Both files first-appear in the same commit. Auditor B observed via filesystem mtimes that the gate file was finalized ~1 minute before the first replay run, but git history alone does not preserve that ordering. This is a permanent fact about Sprint 5's git timeline.

**Status: structurally unresolvable for Sprint 5.** The follow-up commit cannot rewrite Sprint 5's history without `git push --force` to a published branch, which would (a) violate the "preserve the audit trail" discipline and (b) only matter to a reader who already trusts the working tree more than git history. The right fix is the forward-looking discipline change both auditors recommended: for Sprint 6, commit `SPRINT6_GATE_*.md` *first*, push it, then start the work. That makes git timeline the evidence, not document framing.

**Recommendation:** explicitly add this as a Sprint 6 process commitment in the next sprint's pre-flight memo. Worth one line.

---

## Anything New In The Follow-up Worth Flagging

I checked the follow-up commit for new findings. None at the security level. Three small notes:

- **A1.** `docker_metadata/docker_create.stdout` is empty (the create call output the container ID, captured in `docker_create.stdout`). The harness records `docker create` exit code 0 and then runs `docker inspect`. That's the right structure; just noting that a reviewer who only reads `docker_create.stdout` (65 bytes — likely the container ID alone) won't see seccomp evidence there. The seccomp evidence lives in `proc_status.stdout` and `hostconfig_securityopt.txt`. The replay_summary.txt's three explicit metadata-pass records make this navigable; the directory layout is fine.

- **A2.** `proc_status.stdout` is from a sibling `docker create … /bin/sh -c 'grep …'`, not from the guard's own child. So the metadata records *that* a container runs under default Docker seccomp, but it does not directly record the guard's own seccomp filter being installed inside that container. The Sprint 5 main replay (the `pass=11` cases) does verify the guard's filter works inside the container by demonstrating BLOCK on renamed `/bin/rm`, which is the right end-to-end evidence. So this is fine; just noting that the metadata directory alone doesn't tell the whole story — the BLOCK-renamed-rm test is what proves the filter is alive inside the container.

- **A3.** The provenance directory's `commands.txt` lists the queries (`gh repo view`, `gh api`, `docker manifest inspect`) but does not record the *date and time* the queries were run. The mtime on the JSON artifacts (Apr 30 17:24) is the only timestamp available. For a strict audit-trail discipline, including a date stamp in `commands.txt` would prevent ambiguity if the artifacts are ever copied without their mtimes intact. Cheap to add for next time.

None of these block; all are nits. The follow-up commit substantively does what it claims.

---

## What Verified Clean Independently

- Source SHA `07a27fd1...` and binary SHA `e3bdaabf...` unchanged from the Sprint 5 head. The cleanup commit didn't touch the guard. Right move.
- Working tree clean; `git status --short` returns empty.
- Commit `8332e93 Clean Sprint 5 proof metadata` is on `origin/main`.
- The latest sprint5 replay run (`sprint5-docker-20260501T002113Z`) reproduces `pass=11 fail=0` from the candidate's own command log.
- Both Bohr (`subagent_bohr`) and Laplace (`subagent_laplace`) memos are present in `proofs/`.

---

## Sprint 6 Prerequisites (still)

From the Sprint 5 reviews, unchanged by this follow-up:

1. **Pre-register Sprint 6 by committing the gate first.** `git commit SPRINT6_GATE_*.md && git push origin main`, then start the work. This converts pre-registration from document framing to git timeline.
2. **Sprint 6 = interpretation (b)**: pull `ghcr.io/openhands/runtime:1.6.0-nikolaik` (digest already preserved in `proofs/sprint5_provenance/`), exercise it, demonstrate the guard supervising an actual agent process inside the OpenHands runtime — not just an arbitrary process inside a container.
3. **F4 stays deferred** until/unless the demo audience requires fd-stable execution.

Plus three nits from this follow-up audit:
- Add a separate seccomp/NNP metadata record from inside the guard's *child* (not just a sibling docker create) to make the guard's own NNP setting visible.
- Add a date stamp to `commands.txt` in any future `*_provenance/` directories.
- Sprint 6 should include the Carry-Forward table the same way Sprint 5's now does: full enumeration (F1–F8 + A1–A4 + B5–B6 + Sprint 5's two added rows), plus any Sprint 6 carve-outs.

---

## Commands Used For This Audit

```
cd /home/blazingradar/agent-exec-guard-lab

git log --oneline -8
git status --short
git log --diff-filter=A --pretty=format:'%H %ai %s' -- proofs/SPRINT5_GATE_20260430.md
git log --diff-filter=A --pretty=format:'%H %ai %s' -- proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md

ls -la proofs/sprint5_provenance/
ls -la proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/
cat proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/proc_status.stdout
cat proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/hostconfig_securityopt.txt
python3 -c "import json; d=json.load(open('proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/docker_inspect.json')); print(json.dumps(d[0]['HostConfig']['SecurityOpt']))"

cat proofs/sprint5_runs/sprint5-docker-20260501T002113Z/replay_summary.txt
cat proofs/sprint5_provenance/commands.txt
cat proofs/sprint5_provenance/sha256s.txt

grep -nA 40 'Carry-Forward Open Items' proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md

sha256sum guard/usernotify_exec_guard.c bin/usernotify_exec_guard
```

---

## Files

- This audit: `proofs/AUDIT_20260430_sprint5_followup_review.md`
- Follow-up commit: `8332e93 Clean Sprint 5 proof metadata` on `origin/main`
- Subagent audits: `proofs/AUDIT_20260430_sprint5_subagent_bohr.md`, `proofs/AUDIT_20260430_sprint5_subagent_laplace.md`
- Orchestrator audits: `proofs/AUDIT_20260430_sprint5_independent_review_a.md`, `_b.md`
- Sprint 5 proof memo: `proofs/SPRINT5_DOCKER_CONTAINER_PROOF_20260430.md`
- Sprint 5 gate: `proofs/SPRINT5_GATE_20260430.md`
- New evidence directories: `proofs/sprint5_provenance/`, `proofs/sprint5_runs/sprint5-docker-20260501T002113Z/docker_metadata/`
- Source: `guard/usernotify_exec_guard.c` (1258 lines, sha256 `07a27fd1...`)
- Binary: `bin/usernotify_exec_guard` (sha256 `e3bdaabf...`)
