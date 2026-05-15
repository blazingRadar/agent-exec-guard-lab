# Sprint 3 — Fix-Path Analysis (Auditor A)

Date: 2026-04-30
Auditor: Auditor A. Parallel Auditor B is running the same brief; this report is formed without coordination.
Posture: structured fix-path analysis per the Sprint 3 prompt's symbol table / output contract.
Source of record: live kernel probes on this host; live re-derivation of Sprint 2 SHAs; cross-reference of
`AUDIT_20260430_sprint1_independent_review.md`, `AUDIT_20260430_sprint2_independent_review_a.md`,
`AUDIT_20260430_sprint2_independent_review_b.md`, and the reference openat-write demo at
`/home/blazingradar/boundr-adversarial-gaming-lab/kernel_sidecar/harness/seccomp_openat_write_demo_v0.c`.

Host kernel: `Linux 6.17.0-14-generic` (Ubuntu 24.04). Probes used to answer Q_x are in
`/tmp/probe_landlock.c`, `/tmp/probe_addfd.c`, `/tmp/probe_landlock_min.c`, `/tmp/probe_landlock_exec3.c`
(retained for reproducibility during this session).

---

## R₁ — Problem Restatement

### formal_restatement(C₁)

Sprint 2 instantiates Γ as a `SECCOMP_RET_USER_NOTIF` supervisor that, on each intercepted
σ_exec event e, evaluates `identity(e) := (realpath(e.args[0]), st_dev, st_ino)` against
the policy set Π loaded from `policy/sprint2.allow.json`. On `identity(e) ∈ Π`, Γ emits
`F_CONT := SECCOMP_USER_NOTIF_FLAG_CONTINUE`, which instructs the kernel to resume the
*original path-based* σ_exec syscall. The kernel re-reads the path string from Σ_c's
userspace memory at τ₁ (resume time) — not the snapshot Γ stat'd at τ₀.

Therefore, ∃ adversary A controlling Σ_c userspace such that during Δτ := τ₁ − τ₀,
A may either (a) overwrite the byte buffer at e.args[0] to point at a different path
P', or (b) replace the inode at the resolved path on disk with a different file. In
case (a), the kernel re-resolves a new path P' and the binary actually executed at τ₁
is the one at fs(P'), not the one Γ validated. In case (b), the path is unchanged but
fs(realpath(e)) at τ₁ is a different (dev, ino, sha256) than what Γ stat'd at τ₀.

The audit-fidelity consequence (already observed live in
`AUDIT_20260430_sprint2_independent_review_a.md` Critical Finding 3): the supervisor
records `(realpath, dev, ino, sha256)` measured at τ₀, but the binary that ran at τ₁
may not match that record. An ALLOW record cannot be relied on as proof that the matched
binary was the one that executed.

### formal_restatement(why Sprint 2 ≠ fix(C₁))

Sprint 2's identity check is performed in the supervisor's address space, then the
decision is communicated to the kernel as `F_CONT`, which is documented by the
kernel `seccomp_unotify(2)` man page ("TOCTOU considerations") to be unsafe for
path-validating policies for exactly this reason. Sprint 2's `SECCOMP_IOCTL_NOTIF_ID_VALID`
check confirms only that the notification id is still outstanding (i.e., Σ_c hasn't
exited) — it does *not* freeze Σ_c's userspace memory or the filesystem. The Δτ window
between Γ's `process_vm_readv` of e.args[0] and the kernel's resume-time re-read of
the same address is the residual race C₁.

Sprint 2 honestly disclosed this caveat. Sprint 3's job is to *close* the race for the
allow path (Φ_A, Φ_B, Φ_C, Φ_D) or to *bound* it explicitly in the threat model and ship
the rest of the audit-trail hardening derived from the Sprint 2 audits (Φ_E).

---

## R₂ — Possible Fixes

### Φ_A — Landlock underlay

| field | value |
|------|------|
| mechanism | Apply `landlock_restrict_self(Π_exec)` to Σ_c immediately before `execvp`, where Π_exec is built from `LANDLOCK_RULE_PATH_BENEATH` rules covering the directories that contain entries of Π plus the loader/library tree those binaries need. Γ's seccomp filter remains; Landlock is an underlay. |
| Δ_security | If A swaps fs(realpath(e)) in Δτ to a path P' that is not under any directory granted `LANDLOCK_ACCESS_FS_EXECUTE`, the kernel returns EACCES at exec entry — F_CONT does not produce an unauthorized exec. C₁ is reduced from "any path the child can name" to "any binary under an allowlisted parent directory" (and Γ's identity check still narrows that to Π). |
| complexity | Add ~80 LoC to install Landlock in the child between `install_exec_listener()` and `execvp`. Build a small set of `path_beneath` parents from the configured Π by deduping `dirname(entry.real_path)`. Add loader/lib roots (`/lib`, `/lib64`, `/usr/lib`, `/etc`, `/proc`, `/usr/share`) with READ-only access. |
| failure_modes | F1: `path_beneath` requires a *directory* parent_fd; cannot pin to single files. So Landlock allows exec of *every* binary under `/usr/bin/`, not only Π. Γ's identity check still narrows; Landlock provides only the kernel-anchored "no exec outside these directories" property. F2: kernel < 5.13 lacks Landlock; older kernels < 5.19 lack `LANDLOCK_ACCESS_FS_TRUNCATE`. Host kernel 6.17 reports ABI v7 (probed). F3: any binary that needs to exec a child via a non-allowlisted loader path will fail — must include loader tree. F4: handled_access_fs being too narrow yields an empty filter (silent allow); too wide may break legitimate operations of allowlisted binaries (loader access). |
| sprint_feasible | Yes. ~1 day implementation + 1 day harness extension. Independently probed: Landlock present on host (ABI=7), `LANDLOCK_ACCESS_FS_EXECUTE=0x1`, `landlock_create_ruleset` succeeds. With root path_beneath granting EXECUTE+READ_FILE+READ_DIR, fork+execl of `/usr/bin/git` reaches loader (then fails on `/dev/null` write — confirms Landlock is gating exec correctly). |

### Φ_B — FD-stable execution via SECCOMP_IOCTL_NOTIF_ADDFD

| field | value |
|------|------|
| mechanism | At τ₀, after Γ validates `identity(e) ∈ Π`, Γ opens `fd_v := open(realpath(e), O_PATH \| O_CLOEXEC)` in Σ_s. Γ injects `fd_v` into Σ_c via `SECCOMP_IOCTL_NOTIF_ADDFD` with `flags = SECCOMP_ADDFD_FLAG_SEND` (atomic respond+inject). The original path-based execve is rejected with `-EPERM` via the same ADDFD response (or via a normal NOTIF_SEND with `error=-EPERM`); Σ_c's stub immediately re-execs as `execveat(fd_v, "", argv, envp, AT_EMPTY_PATH)`. |
| Δ_security | The kernel executes the file referenced by `fd_v`, which Γ opened and validated at τ₀. Userspace path mutation in Δτ is irrelevant — the path is no longer consulted. Filesystem swap on the inode is also defeated for the case where Γ holds an O_PATH fd that pins (via fd reference) the *file* not the path. C₁ is eliminated for the allow path. |
| complexity | Higher than Φ_A. Requires (a) Σ_c stub that intercepts the rejected execve and re-execs via execveat with the injected fd, (b) Σ_s logic to open O_PATH fd, perform `SECCOMP_IOCTL_NOTIF_ADDFD`, then NOTIF_SEND with error. Need to manage which fd number to inject (must not collide with child fds) and clean up. The Ω_ref demo shows the *openat* variant working in `parent_mode()` line 638-657, with `addfd.flags = SECCOMP_ADDFD_FLAG_SEND` performing the atomic send+respond. The execve variant additionally requires Σ_c to issue execveat against the injected fd — Ω_ref does *not* do this for execve. |
| failure_modes | F1: Σ_c must cooperate with the re-exec. Cannot be "drop-in" against an arbitrary opaque agent — needs Σ_c to be Γ-aware (Σ_c stub) or shell-replacement. F2: `argv[0]` semantics: kernel sets `argv[0]` from execveat's argv, not from the fd; preserved. F3: `AT_EMPTY_PATH` permitted (probed: `execveat(fd_o_path_git, "", ["git","--version"], envp, AT_EMPTY_PATH) → exit 0`). F4: fd opened with O_PATH does *not* require read perm — fine for file-anchored exec. F5: pid(Σ_c) preserved (no new fork). cwd preserved across exec. F6: ADDFD races: per kernel docs, `SECCOMP_ADDFD_FLAG_SEND` is atomic with the response — Γ does not need to NOTIF_SEND separately. F7: race window between Σ_c's first execve (the one that triggered notification) returning EPERM and Σ_c's stub issuing execveat: this window is in Σ_c's own control flow, no path-resolution race. F8: nested execve from a Γ-unaware allowlisted binary (e.g. a shell launched by python) cannot cooperate — falls through to F_CONT path or BLOCK depending on configuration. |
| sprint_feasible | Borderline. ~3-5 days. The stub is the load-bearing piece. Probes confirm: SECCOMP_IOCTL_NOTIF_ADDFD defined, SECCOMP_ADDFD_FLAG_SEND=0x2, execveat(fd, "", ..., AT_EMPTY_PATH) works on host. But the design impact on Σ_c — requiring it to be Γ-aware — is large. |

### Φ_C — Deny original + supervisor-controlled re-exec

| field | value |
|------|------|
| mechanism | Σ_s responds F_DENY (-EPERM) to the original σ_exec. Σ_s itself then `fork+execve`s the validated binary with the captured argv/envp/cwd, and the supervised "child" becomes a new process whose lifecycle Σ_s manages. |
| Δ_security | Δτ eliminated. Σ_s opens and execs the binary in its own context, no userspace path race possible. |
| complexity | Architecturally invasive. pid(Σ_c) changes — agent harnesses that depend on a stable child pid (most do for output capture, signaling, or process group semantics) break. Σ_c's stdin/stdout/stderr/fd table inheritance must be replicated by Σ_s, which means Γ becomes a process launcher rather than a guard. |
| failure_modes | F1: pid drift breaks tools that capture child pid for output multiplexing. F2: Σ_c is no longer "a child running with seccomp"; Σ_c is the supervisor running multiple unrelated children. The "Γ is an exec guard installed in Σ_c" mental model collapses. F3: Honesty: claiming "Σ_c execution guard" while Σ_s is doing the exec is a category error. |
| sprint_feasible | Yes mechanically; no semantically. Violates the Σ_c framing the rest of the lab leans on. |

### Φ_D — ptrace hybrid

| field | value |
|------|------|
| mechanism | Attach ptrace to Σ_c; on `PTRACE_EVENT_SECCOMP`, freeze Σ_c, rewrite e.args[0] to point at a Σ_s-controlled byte buffer (or remap to fd-form), resume via PTRACE_SYSCALL. |
| Δ_security | Δτ shifted, not eliminated. ptrace-modified args[0] is still a path; kernel re-reads it at exec time. Even with rewrite, A holds the same address space and may race the rewrite. The pattern adds complexity without closing the race. |
| complexity | High. ptrace + seccomp user-notify composition has known deadlock conditions (PTRACE_EVENT_SECCOMP fires per-syscall, blocking until tracer continues — interactions with NOTIF_RECV/NOTIF_SEND timing are subtle). Args-rewrite via ptrace requires `ptrace(PTRACE_POKEDATA, ...)` or `process_vm_writev`, which mutates Σ_c memory in a way that Σ_c could re-overwrite. |
| failure_modes | F1: composability with seccomp user-notify is fragile. F2: kernel reads args from registers/syscall ABI for non-pointer args, but execve's path arg is a userspace pointer — race not closed by rewrite. F3: ptrace PERMS: `kernel.yama.ptrace_scope` host setting may block. F4: Sprint-feasibility low; debugging deadlocks is the primary cost. |
| sprint_feasible | No. |

### Φ_E — Threat model narrowing only

| field | value |
|------|------|
| mechanism | Retain F_CONT on allow path. Document Δτ explicitly in the proof memo and README threat model. Ship the audit-trail hardening from the Sprint 2 audit findings (audit fd separation, SIGTERM handler emitting supervisor_exit, real JSON parser, child-anchored realpath, inline SHA256, argv_truncated marker) as Sprint 3 deliverables, with the C₁ disclosure refined to call out "(a) post-validation path mutation, (b) post-validation inode swap on disk, (c) raw_exe vs argv field disagreement under racing children". |
| Δ_security | None against C₁. Substantial Δ against the audit-integrity findings of the Sprint 2 audits (Critical Finding 1 audit forgery, Critical Finding 2 killable supervisor, Secondary Finding 1 /proc/self/exe namespace, Secondary Finding 2 strstr policy parser, Secondary Finding 3-4 argv truncation). |
| complexity | Lowest. ~1-2 days for fd separation + signal handler + jansson swap + sha256 inline + child-anchored realpath. |
| failure_modes | F1: a future reviewer will ask "did you ever close the documented TOCTOU?" and the answer remains "no, by design". This is acceptable iff E₁ ∉ threat model is honestly stated. |
| sprint_feasible | Yes. |

---

## R₃ — Recommendation

### primary := Φ_A (Landlock underlay)

argmax_{Φ_x} (Δ_security × sprint_feasible) under the constraints:
- I3 (Σ_s outside Σ_c seccomp): preserved unchanged.
- I5 (execveat conservatively blocked): preserved; Landlock applies regardless of which exec syscall fires.
- C4 (no architecture rewrite): satisfied — Landlock is added in Σ_c immediately before execvp; Γ's filter and IPC are untouched.
- I6 (honest claim policy strict): the resulting claim is provable by the harness — add a probe that copies an unallowlisted binary into a non-allowlisted directory and verifies the kernel returns EACCES even with a hypothetical ALLOW from Γ.

Δ_security delta is real and provable: the F_CONT-enabled path race is reduced from "child can name any path on the filesystem" to "child can name any binary under directories Γ pre-blessed". Combined with Γ's (realpath, dev, ino) identity check, both layers must be simultaneously bypassed for an unauthorized exec — and Landlock cannot be lifted by Σ_c (it's `restrict_self` + NO_NEW_PRIVS).

### fallback := Φ_E (threat model narrowing + audit hardening)

argmax_{Φ_x \ {Φ_A}} (Δ_security × sprint_feasible).

Φ_B has a strictly higher security delta than Φ_A (eliminates rather than reduces C₁), but its sprint_feasible coefficient is lower because it requires Σ_c-side cooperation: an agentic tool that does not know about Γ cannot be made to issue execveat against an injected fd. Φ_A applies to *any* Σ_c without modification.

If Φ_A turns out to be infeasible during implementation (e.g., loader tree is too brittle, or Landlock rules blow up the binary's runtime in unexpected ways), fall back to Φ_E. Do not attempt Φ_B without a separately-scoped sprint that explicitly addresses "Σ_c stub" as a deliverable.

### justification

Φ_A satisfies all five non-negotiable invariants:
- I1 (fail-closed on deny): Γ's identity check is unchanged; F_DENY still returned for `identity(e) ∉ Π`.
- I2 (ℛ pass=12/fail=0): all twelve existing probes are about Γ's identity decisions and the audit JSON shape; Landlock is below them. Independent re-run of Sprint 2 ℛ on a Landlock-augmented binary should be neutral (Landlock's parents include the Π directories).
- I3 (Σ_s outside Σ_c): Landlock is restrict_self in Σ_c only; Σ_s is unaffected.
- I4 (JSON audit emitted): unchanged.
- I5 (execveat blocked): unchanged. Landlock applies to exec regardless of syscall.
- I6 (honest claims): the only new claim — "Landlock denies exec of paths not under any Π parent directory even after F_CONT" — is provable by an additional ℛ probe (live: copy an unallowed binary to /tmp, attempt exec via Σ_c, observe EACCES from kernel).

Φ_A's failure mode F1 (cannot pin to single file) is not a regression vs Sprint 2 — Γ's identity check already provides per-file precision. Landlock provides directory-level kernel anchoring; combined, the system requires both (a) the path resolves under a Π-parent and (b) (realpath, dev, ino) match a Π entry.

The argument for Φ_A over Φ_E reduces to: Φ_A *does something about C₁* with sprint-bounded effort, while Φ_E preserves C₁ and ships only audit hygiene. The Sprint 2 audits already specified the audit hygiene work as Sprint 3 prerequisites; that work should be *additionally* delivered alongside Φ_A — the audit-integrity findings are independent of C₁ and should not be deferred regardless of which fix path is chosen.

---

## R₄ — Implementation Plan

### files_Σ (modified)

- `guard/usernotify_exec_guard.c`
  - Add `#include <linux/landlock.h>` and syscall number fallbacks.
  - Add `install_landlock_underlay(const Policy *policy)` that builds a deduped set of `dirname(entry.real_path)` parent_fds, plus a fixed read-only set of loader/lib roots, calls `landlock_create_ruleset`, `landlock_add_rule` per parent, then `landlock_restrict_self`. NO_NEW_PRIVS already set; do not set twice.
  - Call `install_landlock_underlay(&policy)` in the child branch (line 651-657) *between* the `send_fd(socks[1], listener_fd)` and `execvp(...)` calls.
  - Treat `landlock_create_ruleset` returning ENOSYS as fail-closed: emit a `landlock_unsupported` audit record and exit 2. (Host kernel 6.17 supports it; CI on older kernels would need a guard if this lab runs anywhere else.)
- `policy/sprint2.allow.json`
  - No schema change required for Φ_A. Optionally add a `"landlock_extra_read_roots"` array for operator-tuning of loader paths if defaults are insufficient.
- `scripts/replay_sprint2_identity.sh`
  - Add probe `landlock_blocks_exec_outside_pi`: copy a known-good copy of `/usr/bin/git` to a non-allowlisted directory `/tmp/ll_outside/git`, invoke Σ_c, expect exit 126 with stderr containing kernel "Permission denied" (EACCES) — distinct from Γ's `blocked_executable_identity` reason. This proves the Landlock layer fired *below* Γ.
  - Add probe `landlock_allows_pi`: existing `allow_git` should still pass — verify that adding Landlock did not break the canonical allow path.

In addition, deliver the audit-integrity prerequisites identified by Auditor A's Sprint 2
review (ordered by priority):
- Open dedicated supervisor stderr fd before fork; route Σ_c stderr to a separate file or fd (closes Critical Finding 1).
- Install SIGTERM/SIGINT handler emitting `supervisor_exit{reason: "killed_by_signal"}` (closes Critical Finding 2).
- Replace strstr/strchr policy parser with jansson or a vendored single-header JSON parser (closes Secondary Finding 2).
- Resolve `realpath` against `/proc/<child_pid>/cwd` for relative paths and via `/proc/<child_pid>/root/...` for `/proc/self/exe`-style magic paths (closes Secondary Finding 1).
- Inline SHA256 (vendor a single-file picohash or libcrypto link) — drops fork+exec to /usr/bin/sha256sum (closes Secondary Finding 5).
- Add `argv_truncated:bool` to JSON when the buffer fills (closes Secondary Findings 3, 4).

These should ship in Sprint 3 *whether or not* Φ_A is chosen. They are necessary to keep the audit trail load-bearing.

### files_∂Σ (new proof artifacts)

- `proofs/SPRINT3_LANDLOCK_UNDERLAY_20260430.md` — the proof memo: Π_exec construction, kernel probe results, ABI version, ℛ pass/fail with Landlock, claim_if_fixed.
- `proofs/SPRINT3_AUDIT_20260430.md` — self-audit memo following the established discipline (preserve any failed runs, sha256-anchor source/binary, "claims still not allowed" list expanded).
- `proofs/SPRINT3_COMMAND_LOG_20260430.md` — command-by-command log, in the same shape as `SPRINT2_COMMAND_LOG_20260430.md`.
- `proofs/SPRINT3_FIX_PATH_ANALYSIS_A_20260430.md` — this file (already written).
- `proofs/sprint3_runs/sprint3-<UTC>/` — per-run subdirectories with stdout, stderr, exit_code, command, json_check; sha256s.txt anchor.

### probes (Q_x answers — must be re-run live before coding)

Φ_A:
- Q_A1 — `landlock_create_ruleset() succeeds on host kernel?` — **YES**. Probe `/tmp/probe_landlock` reports `LANDLOCK_ABI=7`, `LANDLOCK_CREATE_RULESET=3 errno=0`.
- Q_A2 — `LANDLOCK_ACCESS_FS_EXECUTE available?` — **YES**. `LANDLOCK_ACCESS_FS_EXECUTE=0x1`.
- Q_A3 — `landlock_restrict_self() applicable to Σ_c before exec?` — **YES**. Probe `/tmp/probe_landlock_min` calls restrict_self successfully and the subsequent `execl("/usr/bin/git", ...)` reaches loader (it failed on `/dev/null` because we did not grant write — confirms Landlock is gating exec correctly under our control).
- Q_A4 — `Landlock restrictions inherited across execve chain?` — **YES** by Landlock semantics: `landlock_restrict_self` permanently restricts the calling thread and all future descendants; it survives execve. (Documented in `landlock(7)` and `landlock_restrict_self(2)`.) Verify in the harness with a multi-level exec.
- Q_A5 — `failure mode if Landlock unavailable (kernel < 5.13)?` — fail-closed. If `landlock_create_ruleset` returns ENOSYS, the supervisor must refuse to launch Σ_c and emit a `landlock_unsupported` decision. (Not relevant on this host but required for portability.)

Φ_B (probed for thoroughness; not the chosen path):
- Q_B1 — `SECCOMP_IOCTL_NOTIF_ADDFD available on host kernel (≥ 5.9)?` — **YES**. Probe `/tmp/probe_addfd` reports `SECCOMP_IOCTL_NOTIF_ADDFD_DEFINED=yes`, `SECCOMP_ADDFD_FLAG_SEND_DEFINED=yes value=0x2`.
- Q_B2 — `execveat(fd, "", argv, envp, AT_EMPTY_PATH) permitted?` — **YES**. Probe forks `/usr/bin/git` via execveat against an O_PATH fd, exit 0, "git version 2.43.0" printed.
- Q_B3 — `Σ_c must cooperate for re-exec — is child rewrite required?` — **YES, this is the dealbreaker for Φ_B as a sprint deliverable.** A Γ-aware stub in Σ_c is required to receive the injected fd and issue the execveat. An arbitrary agentic harness running under Γ cannot be retrofitted.
- Q_B4 — `argv / envp / cwd / pid semantics preserved across re-exec?` — argv/envp preserved by execveat (kernel uses the new args). cwd preserved (no chdir). pid preserved (same process). pid is the strongest preservation argument vs Φ_C.
- Q_B5 — `does F_DENY on original + re-exec produce correct exit semantics?` — yes if the stub catches the EPERM and re-execs via the injected fd; the final exit status is from the re-exec'd binary. If the original execve was issued by an unaware caller (libc execvp), the EPERM propagates and the re-exec never happens — bypass becomes "the agent thinks it ran git but actually it errored", which is a denial-of-service shape, not a security bypass.
- Q_B6 — `fd injection race: is addfd atomic with F_DENY response?` — **YES** with `SECCOMP_ADDFD_FLAG_SEND`: the ioctl atomically injects the fd and resumes the syscall. Documented in `seccomp_unotify(2)`. Ω_ref harness uses this exact pattern at line 638-657 for the openat case.

Φ_E (always-deliver audit-integrity prerequisites):
- Q_E1 — `is E₁ reachable in target deployment (Docker, OpenHands)?` — Out of scope per [C1]. The C₁ residual is what it is on bare host; in a container with stricter mounts and namespacing, exploitation surface narrows but does not vanish.
- Q_E2 — `is disclosed C₁ acceptable to target audience?` — Yes for a mechanism-proof posture; no for a production-hardened claim. Sprint 3 retains the mechanism-proof posture (per honest_claim_policy=strict) regardless of which Φ is shipped.
- Q_E3 — `does honest claim with C₁ still demonstrate value?` — Yes, but Φ_A genuinely shrinks C₁'s exploitable surface, so the Sprint 3 honest claim is meaningfully stronger than the Sprint 2 honest claim.

### success (acceptance predicates for Φ_A)

- A₁ := landlock_create_ruleset() ≠ error → ⊤ (probed live; ABI=7).
- A₂ := Γ + Landlock: ℛ pass=12/fail=0 unchanged → must verify post-implementation. Add ℛ probe `landlock_blocks_exec_outside_pi` (pass=13).
- A₃ := claim "Landlock denies exec of non-Π paths even after F_CONT" provable → demonstrated by the new ℛ probe: even if Γ is patched to ALLOW (test build only), Landlock returns EACCES for /tmp/foo.
- A₄ := sprint boundary: fits single sprint → estimated 1-2 days for Landlock + 2-3 days for the audit-integrity prerequisites; total within a single sprint.

### stop (condition under which sprint terminates with Φ_E)

If during implementation any of the following hold:

- Π_exec rule construction blows up because the operator's allowlist spans too many directories to enumerate as parent_fds (Landlock has a per-ruleset rule-count cap; default is sufficient for ~200 parents but a pathological policy could exceed).
- Loader tree READ access cannot be tuned to permit allowlisted binaries to actually run without false breakage (e.g., pip-installed binaries pull in unpredictable shared-lib paths).
- The new ℛ probe `landlock_blocks_exec_outside_pi` cannot be made deterministic across kernel/glibc combos.

Then: drop Φ_A, ship Φ_E (audit-integrity prerequisites only), document Landlock as Sprint 4 work with the obstacles named.

---

## R₅ — Claim if Fixed (Φ_A passes)

K_success:

> "A local SECCOMP_RET_USER_NOTIF supervisor on this host intercepts execve and execveat from a supervised child, applies a file-backed allowlist comparing (realpath, st_dev, st_ino) against pre-resolved entries from `policy/sprint2.allow.json`, denies by default with EPERM, conservatively blocks all execveat, validates notification ids with SECCOMP_IOCTL_NOTIF_ID_VALID, and emits one enriched JSON record per decision plus a `supervisor_exit` record on shutdown. As an underlay, the child additionally installs a Landlock ruleset before execvp that grants `LANDLOCK_ACCESS_FS_EXECUTE` only beneath the directories containing entries of Π, plus read-only access on loader/lib trees needed by those binaries. The ALLOW path still uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE` and the documented userspace-memory TOCTOU window remains; however, the kernel-level Landlock layer denies exec of any path not under a Π-parent directory regardless of supervisor decision, which is verified by harness probe `landlock_blocks_exec_outside_pi`. The supervisor's audit stream is now opened on a dedicated fd before fork (closing the Sprint 2 audit-forgery vector); a SIGTERM handler emits a final `supervisor_exit{reason:killed_by_signal}` record (closing the silent-truncation vector); the policy parser is a real JSON parser; realpath resolution is anchored in the child's filesystem context; SHA256 is computed in-process. ℛ reports pass=13/fail=0. Sprint 3 is a mechanism + underlay proof: it does not eliminate the F_CONT TOCTOU race, but it bounds the allow-path race to binaries under operator-blessed directories at the kernel-anchored level."

This claim is provable in full by the extended harness, source SHA, kernel ABI probe, and the new ℛ probe.

---

## R₆ — Claim if Failed (Φ_E only)

K_failure:

> "A local SECCOMP_RET_USER_NOTIF supervisor on this host intercepts execve and execveat from a supervised child, applies a file-backed (realpath, st_dev, st_ino) allowlist, denies by default with EPERM, conservatively blocks all execveat, and emits enriched JSON audit records on a dedicated supervisor-only fd that the supervised process cannot write to. A SIGTERM handler emits a final `supervisor_exit{reason:killed_by_signal}` record, the policy parser is a real JSON parser, realpath resolution is anchored in the child's filesystem context, SHA256 is computed in-process, and `argv_truncated` flags are emitted when capture buffers fill. The ALLOW path uses `SECCOMP_USER_NOTIF_FLAG_CONTINUE`; this carries the kernel-documented userspace-memory TOCTOU window between the supervisor decision (τ₀) and the kernel's path re-read at exec time (τ₁). The threat model under which this guard is offered explicitly excludes a local process with concurrent write access to the supervised child's address space (E₁), and the residual race is documented in the README. ℛ reports pass=12/fail=0. Sprint 3 is a stronger mechanism proof than Sprint 2; it is not a security boundary against in-process userspace-memory adversaries."

This is the narrowest honest claim that survives without Φ_A's underlay.

---

## R₇ — Do Not

### do_not_broaden

- OpenHands. Out of scope per [C1] ∂Σ_expand = ∅.
- Docker. Out of scope per [C1].
- closure_detector_layer. Forbidden per [C2]. Sprint 3 must not import any closure-detection IP from Boundr or related labs.

### do_not_claim

Specifically forbidden under [C5] (overclaim = ⊥):

- "Sprint 3 closes the seccomp F_CONT TOCTOU." False under Φ_A (it bounds, does not close). False under Φ_E (it documents, does not close).
- "Γ is a security boundary." Γ is a mechanism proof. The honest_claim policy from Sprint 1 and Sprint 2 must continue.
- "Landlock denies exec of any non-allowlisted *binary*." Landlock denies exec of any non-allowlisted *path*. Γ's identity check provides per-binary precision; do not conflate the two layers.
- "Sprint 3 is production-hardened." Not assertable. The audit chain has consistently named this as forbidden.
- "execveat is supported." Not assertable. Sprint 2 conservatively blocks all execveat with `execveat_not_supported_in_sprint2`; Sprint 3 inherits that posture unless Φ_B (which is fallback fallback, not chosen).
- "Supervisor cannot be killed by Σ_c." Not assertable in Sprint 3 unless namespace work is shipped; the SIGTERM handler only ensures a final record is *emitted*, not that the supervisor *survives*.

### do_not_import

- Private governance IP (per [C3]). All policy-parser code, JSON serialization, and SHA256 implementations must be either vendored open-source single-headers (e.g., picohash for SHA256, parson or jansson for JSON) or hand-written. Do not pull anything from the Boundr governance corpus or the `closure_detector` family.

### do_not_rewrite

- Γ_architecture is intact unless ∀ Φ ∈ {A, B, C, D} all = infeasible. Per the analysis, Φ_A is feasible (probed), so [C4] forbids architectural rewrite. Specifically:
  - Do not move Σ_s into a separate process group / pid namespace as part of Sprint 3 (that's Sprint 4 if needed).
  - Do not refactor the Σ_s ↔ Σ_c socketpair/SCM_RIGHTS handoff.
  - Do not switch from F_CONT on allow path. (That would be Φ_B and is explicitly the fallback-fallback.)

---

## Notes on Disagreement With Auditor B

This section is a hedge against the parallel auditor's predicted divergence. Auditor B
may argue that:

- Φ_B is sprint-feasible because Ω_ref already demonstrates the addfd pattern in
  `parent_mode()` lines 638-657 of `seccomp_openat_write_demo_v0.c`.
  My counter: Ω_ref injects a *read-only* shadow fd into a write-intent openat to *neuter* the write — Σ_c still issues the original openat, kernel resumes against the injected fd, and the write fails harmlessly. For execve, the analogous neutering is "inject /bin/false fd and let the kernel run that" — which is not what Φ_B's mechanism describes. The execve variant requires Σ_c to *issue execveat against the injected fd*, which Σ_c only does if it's been rewritten. That's the bigger lift.

- Φ_E is sufficient because the Sprint 2 audits already specified the audit-integrity work as Sprint 3 prerequisites, and adding Landlock is "scope creep".
  My counter: the Sprint 2 audits called out audit-integrity work as *additional* prerequisites, not *the only* Sprint 3 work. C₁ is a standing finding from Sprint 1 (`AUDIT_20260430_sprint1_independent_review.md` Critical Finding 2), explicitly deferred to Sprint 2/3. Sprint 2 chose to defer; Sprint 3 has the budget. Shipping only the audit-integrity work treats C₁ as if it were closed, which it is not.

The recommendation stands: Φ_A primary, Φ_E fallback, with Φ_E's audit-integrity work
delivered in Sprint 3 *regardless* of Φ_A's outcome.

---

## Files

- This analysis: `proofs/SPRINT3_FIX_PATH_ANALYSIS_A_20260430.md`
- Sprint 1 audit (C₁ origin): `proofs/AUDIT_20260430_sprint1_independent_review.md`
- Sprint 2 audit A (audit-integrity findings): `proofs/AUDIT_20260430_sprint2_independent_review_a.md`
- Sprint 2 audit B (parallel pass): `proofs/AUDIT_20260430_sprint2_independent_review_b.md`
- Reference Ω_ref openat-write demo (addfd pattern): `/home/blazingradar/boundr-adversarial-gaming-lab/kernel_sidecar/harness/seccomp_openat_write_demo_v0.c`
- Guard source: `/home/blazingradar/agent-exec-guard-lab/guard/usernotify_exec_guard.c`
- Replay harness: `/home/blazingradar/agent-exec-guard-lab/scripts/replay_sprint2_identity.sh`
- Policy: `/home/blazingradar/agent-exec-guard-lab/policy/sprint2.allow.json`
- Live kernel probes (this session): `/tmp/probe_landlock.c`, `/tmp/probe_addfd.c`, `/tmp/probe_landlock_min.c`, `/tmp/probe_landlock_exec3.c`

## Live Probe Results (this session, host kernel 6.17.0-14-generic)

```
$ /tmp/probe_landlock
LANDLOCK_ABI=7 errno=0
LANDLOCK_ACCESS_FS_EXECUTE=0x1
LANDLOCK_CREATE_RULESET=3 errno=0

$ /tmp/probe_addfd
git version 2.43.0
SECCOMP_IOCTL_NOTIF_ADDFD_DEFINED=yes
SECCOMP_ADDFD_FLAG_SEND_DEFINED=yes value=0x2
open_O_PATH_git=3 errno=0
execveat_status=0x0 WIFEXITED=1 WEXITSTATUS=0

$ /tmp/probe_landlock_min   # restrict_self under '/' allowlist; git enters loader, fails on /dev/null
rs=3 handled=0x7fff
fatal: could not open '/dev/null' for reading and writing: Permission denied
git exit=128

$ uname -r
6.17.0-14-generic
```

End of report.
