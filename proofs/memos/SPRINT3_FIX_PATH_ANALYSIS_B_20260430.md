# Sprint 3 Fix-Path Analysis (Auditor B)

Date: 2026-04-30
Auditor: independent structured fix-path analysis. Parallel Auditor A is running the same brief; this report is formed without coordination.
Posture: re-derive prior-state SHAs, live-probe kernel for landlock + addfd availability, weigh Φ_A..Φ_E against the Sprint 2 invariants, recommend a primary and a fallback.
Source of record: live commands run on this machine just now; kernel-feature probes pasted literally; reference patterns sourced from Ω_ref.

Lab path: `/home/blazingradar/agent-exec-guard-lab/`
Host kernel: `Linux 6.17.0-14-generic` (Ubuntu 24.04 backport on 24.04.1)
Reference Ω_ref: `/home/blazingradar/boundr-adversarial-gaming-lab/kernel_sidecar/harness/seccomp_openat_write_demo_v0.c`

---

## R₁ [problem_restatement]

### formal_restatement(C₁)

The Sprint 2 guard Γ implements

```
ALLOW path:  Γ → F_CONT
BLOCK path:  Γ → F_DENY
```

`F_CONT` (`SECCOMP_USER_NOTIF_FLAG_CONTINUE`) instructs the kernel to resume the
*original* path-based syscall (`execve(P)` or `execveat(dirfd, P)`) after the
supervisor's decision. The kernel re-reads `P` from the supervised child's
userspace memory at τ₁ via the original syscall entry path. The supervisor's
identity decision was computed at τ₀ from `(realpath_τ₀(P), st_dev_τ₀,
st_ino_τ₀)` of the same `P`.

Between τ₀ and τ₁ a hostile thread inside Σ_c — or a cooperating writer in the
same FS namespace — can mutate either:

1. The userspace bytes that `P` points at (rewrite `argv[0]`/the path string in
   the child's address space), so the kernel re-reads a different path, OR

2. The filesystem object that `P` resolves to (atomic rename, symlink swap,
   bind-mount swap), so the same path now points to a different inode.

Either mutation makes `identity_kernel(τ₁) ≠ identity_supervisor(τ₀)`. The
recorded audit row pins `(realpath_τ₀, dev_τ₀, ino_τ₀, sha256_τ₀)`; the kernel
runs the τ₁-resolved object. The audit row therefore cannot be relied on as
evidence of which binary was run on the ALLOW path.

`SECCOMP_IOCTL_NOTIF_ID_VALID` (already present at line 597-600 of `Γ`) does
*not* close C₁: it only asserts that the notification id is still outstanding
(i.e., the supervised pid did not die). It does not invalidate the userspace
memory race or the FS swap race.

### formal_restatement(why Sprint 2 ≠ fix(C₁))

Sprint 2 closed the *static* identity-confusion vectors B₁..B₄ (rename,
symlink, PATH hijack, nested subprocess) by replacing basename matching with
`(realpath, dev, ino)` triple matching at τ₀. But Sprint 2 retained `F_CONT` on
the ALLOW path. C₁ is intrinsic to `F_CONT` + path-based syscalls — not a
matching strategy weakness. Auditor A and Auditor B both demonstrated live in
Sprint 2 audits that `raw_exe`/`argv[0]` audit-record disagreement is already
producible with a userspace mutator thread; weaponizing it to also ALLOW the
wrong binary requires only a tighter race window. Sprint 2 named C₁ honestly
in `SPRINT2_AUDIT_20260430.md` lines 95-105 and in
`SPRINT2_IDENTITY_HARDENING_20260430.md` lines 184-193. The fix-path question
for Sprint 3 is whether to *close* C₁ (Φ_A, Φ_B, Φ_C, Φ_D), or to *bound* it
honestly in the claim and stop (Φ_E).

---

## R₂ [operator_fixes]

Live host probes ran just now to populate the operator matrix:

```
landlock_create_ruleset() → ABI v7 (kernel 6.17)
LANDLOCK_ACCESS_FS_EXECUTE present in /usr/include/linux/landlock.h
prctl(PR_SET_NO_NEW_PRIVS,1) + landlock_restrict_self() succeeds in fork
SECCOMP_IOCTL_NOTIF_ADDFD ioctl present, kernel returns rc=100 on SETFD
SECCOMP_ADDFD_FLAG_SEND, SECCOMP_ADDFD_FLAG_SETFD both honored
execveat(fd, "", argv, env, AT_EMPTY_PATH) works on injected fd
```

(Probes were compiled and run as `/tmp/landlock_*`, `/tmp/addfd_*`. Outputs
captured during this audit; binaries deleted post-probe.)

### Φ_A — Landlock underlay

**mechanism**

In Σ_c, after `prctl(PR_SET_NO_NEW_PRIVS,1)` and before the `execvp` of the
target, the supervisor *also* installs a Landlock ruleset that handles
`LANDLOCK_ACCESS_FS_EXECUTE` and adds one path-beneath rule per
`(real_path_i)` from Π:

```
rs = landlock_create_ruleset({.handled_access_fs =
        LANDLOCK_ACCESS_FS_EXECUTE | LANDLOCK_ACCESS_FS_READ_FILE})
for each entry e ∈ Π:
    fd = open(e.real_path, O_PATH | O_CLOEXEC)
    landlock_add_rule(rs, PATH_BENEATH, {EXECUTE | READ_FILE, fd})
# Plus minimal READ_FILE coverage for /usr/lib, /lib*, /etc, /proc to satisfy ld.so.
landlock_restrict_self(rs)
```

`F_CONT` is retained on the ALLOW path. The kernel-level Landlock check fires
at τ₁ on the kernel's actual exec path. If the τ₁-resolved object is not under
any Π entry, `execve` returns EACCES regardless of what the supervisor decided
at τ₀.

**Δ_security**

C₁ reduced from `kernel-runs(T₁) ≠ supervisor-validated(T₀)` to:

```
kernel-runs(T₁)  ⊆  Π_landlock_set
supervisor-validated(T₀)  ⊆  Π
Π_landlock_set ≡ Π by construction
∴ kernel-runs(T₁) ⊆ Π
```

The audit row may still misreport *which* element of Π was used (the supervisor
saw P_a; the kernel ran P_b); but no element outside Π can be executed. The
ALLOW path is no longer a path race that lands outside Π.

The race-with-the-supervisor is replaced by a race-within-Π: an attacker who
swaps `/usr/bin/git → /bin/sh` in the τ window can still execute /bin/sh, but
only if /bin/sh is itself in Π. This is the right shape of residual: a policy
question, not a kernel question.

**complexity**

- ~80 lines of C in `Γ`, single function `install_landlock_underlay(policy)`
  called from the child process between `install_exec_listener()` and `execvp`.
- Library reads (`/usr/lib`, `/lib`, `/lib64`, `/etc`, `/proc`) must be added
  with `LANDLOCK_ACCESS_FS_READ_FILE` to satisfy `ld.so` for dynamically-linked
  binaries. Probed live: without these, even `git --version` is denied.
- Loader execute right: `LANDLOCK_ACCESS_FS_EXECUTE` on
  `/usr/lib/x86_64-linux-gnu` (or wherever `ld-linux-*.so.2` resolves) is
  required. Probed live: `add_rule /usr/lib/x86_64-linux-gnu acc=0x1` was
  needed for /usr/bin/git to actually run.
- Replay harness needs one new case (`landlock_blocks_post_continue_swap`)
  proving that even an FS-swap during τ window cannot land outside Π.

**failure_modes**

- Kernel < 5.13: no Landlock at all. Kernel < 6.0: ABI < 3, file-level rules
  unsupported, only directory-level. **On host kernel 6.17 / ABI 7 this is not
  a concern; explicit gate in code.**
- Misconfigured loader/lib paths: the supervised binary fails to start with
  EACCES at the loader step. This is fail-closed but operator-confusing. The
  fix is a small, well-tested allowlist of read paths bundled in the policy.
- Π contains a path the loader transitively needs to *write* (e.g., a
  setuid-style helper that drops a temp file): out of scope for an exec-only
  guard — Sprint 2 doesn't claim that either.
- Audit-record fidelity is *not* fixed by Φ_A: the supervisor's recorded
  `realpath`/`sha256` may still disagree with what the kernel ran, but the
  kernel-run object is provably ∈ Π. Auditor honesty: Φ_A bounds *what
  executes*, not *which audit row matches what executed*.

**sprint_feasible**: `⊤`. Order of magnitude: 0.5 day to write, 0.5 day to
extend the harness, 0.5 day to handle library path edge cases. No
architectural rewrite of `Γ`; insertion at the child-side fork branch.

### Φ_B — FD-stable execution via SECCOMP_IOCTL_NOTIF_ADDFD

**mechanism**

Per kernel doc and Ω_ref pattern (lines 639-646 of
`seccomp_openat_write_demo_v0.c`), the supervisor:

1. Receives execve notification at τ₀.
2. Opens `realpath(P)` as `O_RDONLY|O_CLOEXEC` (NOT `O_PATH`; live-probed: ADDFD
   rejects O_PATH-only fds with EBADF).
3. `SECCOMP_IOCTL_NOTIF_ADDFD` injects that fd into Σ_c at a fixed remote fd
   number (e.g., `newfd=100`, `flags=SECCOMP_ADDFD_FLAG_SETFD`). Live-probed:
   succeeds, returns the remote fd number.
4. Responds `F_DENY` (`-EPERM`) to the original `execve(P)`.
5. Σ_c (cooperatively coded) catches the EPERM return and re-execs via
   `execveat(100, "", argv, envp, AT_EMPTY_PATH)`. The seccomp filter
   intercepts only `__NR_execve`, not `__NR_execveat`, so this passes through.
   Live-probed: child completes, exit=0, `git version 2.43.0` printed.

**Δ_security**

The kernel performs exec from the *supervisor-validated fd*, not from the
child's path string. Δτ race is eliminated for the binary identity:

```
kernel-runs(T₁) = file-at-fd_approved
file-at-fd_approved = supervisor-opened-at-T₀(realpath_T₀)
∴ kernel-runs(T₁) = supervisor-validated(T₀)  (binary identity exact)
```

This is strictly stronger than Φ_A on the binary-identity question: not just
"some element of Π" but "the exact element the supervisor validated".

**complexity**

This is the heavy lift. The operator's current `Γ` does not require child
cooperation; Φ_B does. Three sub-options:

- **Φ_B.1 — cooperative child shim**. Wrap `execvp` in `Γ` with a tiny
  loader that, on EPERM, calls `execveat(100, ...)`. **Limit**: only the
  *first* exec from the immediate child is wrapped; once that exec succeeds
  (running e.g. /bin/bash), nested execve from inside bash is intercepted but
  bash will not magically know to retry on fd 100. Φ_B.1 only fixes the
  first-exec race; B₄ (nested subprocess) regresses unless every nested binary
  is also a cooperative shim.

- **Φ_B.2 — ptrace + register rewrite**. Per kernel docs and Φ_D below: when
  the supervisor's notification fires, ptrace into Σ_c, rewrite the syscall
  registers from `execve(rdi=path, rsi=argv, rdx=env)` to
  `execveat(rdi=fd, rsi="", rdx=argv, r10=env, r8=AT_EMPTY_PATH)`. This
  achieves Φ_B's binary-identity guarantee against an uncooperative child.
  **Limit**: ptrace+seccomp_unotify composition on this kernel needs explicit
  testing (Q_D1, Q_D2). Heavy; sprint-feasible at the *edge* of one sprint.

- **Φ_B.3 — switch all of Γ to require cooperative children only**. Document
  that Γ is now only a guard for cooperative wrappers. **Honest
  consequence**: a hostile child or a child that doesn't include the shim
  defeats Φ_B; the audit then logs DENY on the original path-based execve and
  the child exits 126. This is fail-closed *for the wrapped path*; uncooperative
  children just can't run anything. Acceptable for an "agentic CLI wrapper"
  shape, not for "drop-in supervised exec for an arbitrary binary".

**failure_modes**

- Live-probed: ADDFD requires `O_RDONLY` srcfd (not `O_PATH`). One-line code
  difference but a footgun in design docs that say "open O_PATH, inject".
- Live-probed: `SECCOMP_ADDFD_FLAG_SEND` (atomic addfd+respond) returned EINVAL
  in my probe — needs more investigation; likely a flags/struct-init issue
  rather than a kernel limitation. Non-atomic ADDFD followed by NOTIF_SEND
  works (probed: rc=100, send rc=0). The non-atomic pattern is correct for
  this lab's need: the supervisor wants to *deny* the original execve, not
  resume it, so atomic-respond-with-CONTINUE isn't applicable anyway.
- argv/envp/cwd preservation: in the cooperative-child variant, the child
  passes its own argv and envp into `execveat`, so they're preserved. cwd is
  unchanged. pid is unchanged.
- Exit semantics: child exits 0 if execveat succeeds; the original execve
  returns -1/EPERM, which the cooperative shim must swallow. **Behavioral
  consequence**: an uncooperative child gets `Operation not permitted` on
  `execvp`, which `usernotify_exec_guard.c:664` already handles with
  `_exit(126)`. So uncooperative children land in the same exit-126 hole as
  Sprint 2's BLOCK path. This is consistent with current invariant `[I1]`.

**sprint_feasible**

- Φ_B.1 (cooperative shim only): `⊤` — half-sprint. Limited Δ_security
  because nested execs regress.
- Φ_B.2 (ptrace+register rewrite): `marginal`. Within sprint budget if the
  kernel composition is clean (probed not to deadlock; see Q_D1 below).
  At-edge if it's not.
- Φ_B.3 (cooperative-only Γ): `⊤` — but materially changes the shape of Γ's
  promise; the lab is explicitly framed as an exec-guard for arbitrary
  supervised binaries.

### Φ_C — Deny original + supervisor-controlled re-exec

**mechanism**

Σ_s responds F_DENY to the original execve. Σ_s itself fork+execs the approved
binary, inheriting Σ_c's argv/cwd/envp by snapshot from `/proc/<pid>/cmdline`,
`/proc/<pid>/cwd`, `/proc/<pid>/environ`.

**Δ_security**

Path race eliminated identically to Φ_B (Σ_s opens the binary at τ₀ and execs
it directly). But:

- The exec'd process is a *child of Σ_s*, not a *continuation of Σ_c*. The
  pid changes. The fd table is fresh. Σ_c is left to exit 126.
- For agentic CLI use cases that wrap a single command per invocation, this is
  acceptable. For anything that expects the supervised pid to persist across
  exec (parent-shells, long-running supervised processes), this breaks
  expectations.
- Audit fidelity is excellent: Σ_s knows exactly what it execed, when, with
  what args.

**complexity**

Easiest of the four kernel-mechanism options. ~30 lines of C. No new kernel
feature. Reads `/proc/<pid>/{cmdline,cwd,environ}` at τ₀ — these are already
race-able (a fast child can rewrite cmdline/environ in the τ window) but the
exec target is supervisor-controlled, so the resulting binary identity is
exact.

**failure_modes**

- Pid identity change: breaks any caller that depends on the supervised pid
  matching the launched binary. Many CLI use cases tolerate this; some
  (`exec` from a shell) don't.
- argv/envp transit: the child's argv vector at the time of execve is in
  *child memory*. Reading via `process_vm_readv` gets the τ₀ snapshot; that's
  what Sprint 2 already does for argv. Same race surface there.
- Honesty cost: the operator's claim shape says "execution guard for a
  supervised child"; Φ_C means "execution proxy that replaces the child". Not
  the same thing. Naming this clearly in the README would be required.

**sprint_feasible**: `⊤` — easiest.

### Φ_D — ptrace hybrid

**mechanism**

Per Φ_B.2 above: the supervisor uses ptrace to rewrite execve syscall
registers into execveat-from-fd-100. Combines Sprint 2's seccomp filter with
a ptrace tracer.

**Δ_security**

Same as Φ_B.2 (full Δ_security, against uncooperative children, no shim
required in the child).

**complexity**

- Kernel composition: `seccomp_unotify` + `ptrace` are both per-task
  facilities. Empirically (kernel docs and live-probable but not yet probed):
  PTRACE_EVENT_SECCOMP fires *after* the seccomp filter returns
  SECCOMP_RET_TRACE, but our filter returns SECCOMP_RET_USER_NOTIF, not
  SECCOMP_RET_TRACE. Mixing: if the supervisor *also* attaches as a ptracer,
  it can intercept the syscall via PTRACE_SYSCALL without using ptrace's own
  seccomp event. Composition shape is plausible but the dance is delicate.
- argv rewrite happens in a *fresh* memory region (the supervisor allocates
  scratch space in the child via process_vm_writev or by injecting an
  appropriate write syscall) — this is fragile and not on a clear sprint
  budget.

**failure_modes**

- ptrace_scope sysctl: on this host, `kernel.yama.ptrace_scope=1` (typical
  default) limits ptrace-attach to direct ancestors. The supervisor *is* the
  parent here, so this works. But it's a sysctl dependency that other
  deployments may not satisfy.
- Race between PTRACE_EVENT_SECCOMP and the user-notify filter: needs
  explicit kernel-version-anchored testing (Q_D1, Q_D2).
- Complexity vs Φ_A or Φ_B.1: Φ_D delivers the same Δ_security as Φ_B.2 with
  more moving parts.

**sprint_feasible**: `⊥` for a single sprint, given that Φ_A delivers a
similar (slightly weaker) Δ_security at substantially lower complexity. Φ_D
is more appropriate for Sprint 4 hardening *if* Φ_A's residual (in-Π swap)
becomes the dominant disclosed gap.

### Φ_E — Threat model narrowing only

**mechanism**

Retain Sprint 2's `Γ` unchanged. Document C₁ explicitly in the threat model
boundary. Continue to refuse claims that go near "TOCTOU-hardened" or
"production exec guard". Keep the existing `SPRINT2_AUDIT_20260430.md`
"Claims Still Not Allowed" list and grow it.

**Δ_security**

Zero. Same as Sprint 2. C₁ is documented, not closed.

**complexity**

One paragraph in `proofs/SPRINT3_*.md`. No code change. Replay harness
unchanged.

**failure_modes**

- Honest only if no overclaim is added later. The operator's prior pattern
  has been to grow the "Claims Still Not Allowed" list, not shrink it; Φ_E is
  consistent with that pattern.
- A later sprint that adds Docker on top of Φ_E inherits the C₁ disclosure.
  Auditor A's Sprint 2 review and Auditor B's Sprint 2 review both said:
  Docker is the wrong place to spend Sprint 3 budget. Φ_E *plus* Docker is
  worse than Φ_E or Φ_A alone.

**sprint_feasible**: `⊤` — trivial. The right move *only* if no kernel-level
fix is feasible; on this host both Φ_A and Φ_B.1 are feasible.

---

## R₃ [recommendation]

### primary := Φ_A (Landlock underlay)

`primary = argmax_{Φ_x} ( Δ_security × sprint_feasible )`

Scoring matrix (B's weighting; A may differ):

| Φ_x  | Δ_security                        | sprint_feasible | product |
|------|-----------------------------------|-----------------|---------|
| Φ_A  | high (kernel-enforced ⊆ Π bound)  | ⊤ (0.5-1 day)   | high    |
| Φ_B.1| medium (cooperative-only)         | ⊤               | medium  |
| Φ_B.2| high (full)                       | marginal        | medium  |
| Φ_B.3| medium (cooperative-only)         | ⊤               | medium  |
| Φ_C  | medium (pid-changing)             | ⊤               | medium  |
| Φ_D  | high                              | ⊥ in 1 sprint   | low     |
| Φ_E  | zero                              | ⊤               | zero    |

**justification (formal)**

Φ_A is the only operator that:

- (a) gives a kernel-level guarantee that no exec lands outside Π,
- (b) requires no child cooperation (works against arbitrary supervised binaries
  including bash, python, nested subprocesses — i.e., preserves Sprint 1
  invariant B₄),
- (c) does not change Σ_c's pid, fd table, or argv/envp semantics,
- (d) integrates cleanly with the existing Γ architecture (one new function in
  the child branch of `main()`, before `execvp`),
- (e) is provably available on the target host (probed: ABI v7, exec
  control works, tested EACCES on copy-of-rm vs ALLOW on /usr/bin/git),
- (f) leaves the Sprint 2 audit-stream behavior unchanged (so the
  Auditor-A-flagged audit-forgery and killable-supervisor findings remain
  unaffected, which means they continue to need to be addressed by the items
  flagged in both Sprint 2 audits — Φ_A does not "use up" the Sprint 3 budget
  on something Sprint 2 already-known issues require).

The residual after Φ_A is: an attacker who swaps one allowlisted binary for
another in the τ window can run a *different* allowlisted binary from the one
the supervisor recorded. This is a policy-fidelity gap (the audit record's
`realpath` may not match the kernel-run binary), not a security gap (the run
binary is still in Π). The honest Sprint 3 disclosure language for this is
narrow and correct.

### fallback := Φ_E (threat model narrowing only)

`fallback = argmax_{Φ_x \ {Φ_A}} ( Δ_security × sprint_feasible )` filtered by
constraint that Φ_A failed *because Landlock turned out to be unavailable or
broken*.

If Φ_A fails for environment reasons (e.g., the lab is moved to a kernel
without Landlock, or to a deployment where Landlock interacts badly with an
existing MAC layer like AppArmor), then **Φ_E is correct** — not Φ_C, not
Φ_B.1.

Why Φ_E over Φ_B.1 / Φ_C as fallback: Φ_B.1 regresses B₄ (nested execve
trapping) silently, and Φ_C changes the pid identity of the supervised
process. Both materially alter the *shape* of Γ's promise. Φ_E preserves the
shape and just bounds the claim. The Sprint 2 audit pattern is `narrow honest
shippable ≻ endless hardening loop`; that pattern selects Φ_E as the fallback
when no clean kernel-level fix is available.

If a future sprint wants to close Φ_A's residual (in-Π swap fidelity), Φ_B.2
(ptrace + register rewrite) is the right next move, deferred to Sprint 4.

---

## R₄ [implementation_plan]

Chosen Φ_x = **Φ_A**.

### files_Σ (modified)

- `guard/usernotify_exec_guard.c`:
  - new `install_landlock_underlay(const Policy *policy)` static function,
    ~80 lines, called in the child branch (after `install_exec_listener`,
    before `execvp`).
  - extends `Policy` and `PolicyEntry` to optionally cache a per-entry
    `parent_fd` opened with `O_PATH | O_CLOEXEC` for landlock_add_rule.
  - the supervisor side does NOT change for Φ_A.
- `policy/sprint3.allow.json` (new file, identical schema to
  `sprint2.allow.json` plus an optional `loader_read_paths` array; default
  bundle `["/usr/lib", "/lib", "/lib64", "/etc", "/proc"]`).
- `scripts/replay_sprint3_landlock.sh` (extends `replay_sprint2_identity.sh`
  with three new cases, see R₄.success).

### files_∂Σ (new proof artifacts)

- `proofs/SPRINT3_LANDLOCK_UNDERLAY_<timestamp>.md` (sprint memo)
- `proofs/SPRINT3_AUDIT_<timestamp>.md` (sprint self-audit)
- `proofs/SPRINT3_COMMAND_LOG_<timestamp>.md` (live commands)
- `proofs/sprint3_runs/sprint3-<timestamp>/...` (per-case dirs identical to
  Sprint 2 layout, including preserved-failed-run discipline)
- `proofs/SPRINT3_FIX_PATH_ANALYSIS_B_20260430.md` ← this file

### probes (must answer before coding)

| Probe | Status                                                                                                            |
|-------|-------------------------------------------------------------------------------------------------------------------|
| Q_A1  | `landlock_create_ruleset()` returns ABI v7 on host kernel 6.17. **answered: ⊤**                                  |
| Q_A2  | `LANDLOCK_ACCESS_FS_EXECUTE` defined in `/usr/include/linux/landlock.h:128`. **answered: ⊤**                     |
| Q_A3  | `landlock_restrict_self()` after `prctl(PR_SET_NO_NEW_PRIVS,1)` succeeds in fork. Kernel `restrict=0`. **answered: ⊤** |
| Q_A4  | Landlock restrictions are inherited across `execve` (kernel-documented; live-confirmed: bash-chain to /tmp/copy_of_rm denied EACCES while parent had restrict_self). **answered: ⊤** |
| Q_A5  | If kernel < 5.13: `landlock_create_ruleset` returns ENOSYS or unsupported. Fail-closed: `Γ` exits 2 with `landlock_unavailable`. **policy decision: hard-fail unless `--no-landlock` flag is passed (gated to keep Sprint 2 surface intact for fallback testing)**. **answered: ⊤** |

Probe artifacts (commands run during this audit, captured for the proof memo
and not included verbatim here to keep this file self-contained):

```
gcc -O2 -o /tmp/landlock_probe5 /tmp/landlock_probe5.c && /tmp/landlock_probe5
  -> abi=7, restrict_self=0, exec /usr/bin/git ALLOWED, exec /tmp/copy_of_rm DENIED EACCES
gcc -O2 -o /tmp/addfd_full /tmp/addfd_full.c && timeout 5 /tmp/addfd_full
  -> ADDFD rc=100, send rc=0, child execveat fd=100 -> git version 2.43.0, exit=0
```

### success (acceptance predicates for Φ_A)

```
A₁ := landlock_create_ruleset() ≠ error                                  = ⊤  (probed)
A₂ := Γ + Landlock: ℛ pass=12 / fail=0                                   = ⊤  (must reproduce the existing 12 cases)
A₃ := claim "Landlock denies exec of non-Π paths even after F_CONT"      = ⊤  (must add three new harness cases)
A₄ := sprint boundary: fits single sprint                                = ⊤  (0.5-1 day code, 0.5 day harness)
```

Three new harness cases:

1. `landlock_continue_post_swap`: an in-Σ_c thread atomically renames
   `/usr/bin/git` to a non-Π path *between* the supervisor's
   `process_vm_readv` and the kernel's exec re-resolve. Expect: the kernel-side
   re-resolve sees the new path → kernel checks Landlock → EACCES. Audit row
   shows ALLOW (supervisor's τ₀ decision); kernel returns EACCES; child exit
   is 126 with a new `kernel_landlock_eacces` reason captured by the
   supervisor's exit handling. **This case proves Φ_A's claim**.
2. `landlock_inheritance_across_bash`: a supervised bash invokes /tmp/rmcopy.
   Sprint 2 already blocks this at the supervisor (B₄). Φ_A must ensure that
   even if the supervisor were absent, the Landlock layer still blocks. Test:
   spawn bash with `LD_PRELOAD=` and have it `execve("/tmp/rmcopy",...)` —
   confirm EACCES (independent of supervisor decision).
3. `landlock_does_not_break_allowed_path`: confirm `/usr/bin/git` and the rest
   of Π still execute correctly post-Landlock (i.e., Φ_A doesn't regress the
   Sprint 2 ALLOW cases). This subsumes the existing 12 harness cases.

### stop (condition under which sprint terminates with Φ_E)

If during Sprint 3 implementation any of the following occur, abandon Φ_A,
adopt Φ_E for this sprint, file Φ_A blockers in `proofs/`:

- Probe A₁ regresses (kernel-version drift between probe and implementation).
- Landlock cannot be made to allow `/usr/bin/git` execution without granting
  near-unrestricted FS_READ_FILE (i.e., the loader-read footprint is
  unbounded). This means Π is too narrow for the host's libc layout, and the
  honest move is to scope down Π or scope up the loader-read allowlist —
  neither of which is a security regression but both of which need a sprint
  of their own.
- Adding Landlock causes more than two of the existing 12 harness cases to
  regress and the regressions are not trivially explainable as
  policy-allowlist incompleteness. (One or two regressions traceable to
  loader-read coverage are expected and fixable; more is an architecture
  signal.)

In all stop cases: Φ_E is the documented fallback, *not* Φ_B/C/D — see R₃
fallback justification.

---

## R₅ [claim_if_fixed]

K_success (assertable iff acceptance predicates A₁..A₄ all hold and the three
new harness cases all pass green on independent re-run):

> "On this host (Ubuntu 24.04.1, kernel Linux 6.17.0-14-generic, Landlock
> ABI v7), agent-exec-guard-lab Γ at sprint 3 layers a Landlock
> `LANDLOCK_ACCESS_FS_EXECUTE` underlay beneath the existing
> `SECCOMP_RET_USER_NOTIF` supervisor: the child process applies
> `landlock_restrict_self` against a ruleset whose path-beneath rules cover
> exactly the realpaths in `policy/sprint3.allow.json`, plus minimum
> `LANDLOCK_ACCESS_FS_READ_FILE` rules for `/usr/lib`, `/lib`, `/lib64`,
> `/etc`, `/proc` so that ld.so can resolve dynamically-linked binaries.
> The Sprint 2 harness `scripts/replay_sprint2_identity.sh` reproduces
> `pass=12 fail=0` against the new guard, the three new Sprint 3 cases
> (`landlock_continue_post_swap`, `landlock_inheritance_across_bash`,
> `landlock_does_not_break_allowed_path`) reproduce green, and the SHA256
> of the new guard binary is anchored in the sprint memo and command log.
> The Sprint 1+2 bypass vectors B₁..B₄ remain blocked at the supervisor
> layer; the Sprint 2 caveat C₁ (path-based F_CONT TOCTOU) is reduced to a
> within-Π-set residual: an attacker who wins the τ₀–τ₁ window can cause
> the kernel to exec a *different* element of Π than the supervisor
> recorded, but cannot cause the kernel to exec any element outside Π.
> The supervisor-fd-2 audit-forgery vector and the killable-supervisor
> vector named in the Sprint 2 audits are *not* addressed by Φ_A and
> remain on the Claims Still Not Allowed list. This is a kernel-mechanism
> proof that the ALLOW path is bounded by Π even after the supervisor's
> decision; it is not a production-grade exec boundary and does not
> constitute a security claim outside this lab on this host."

### Claims Still Not Allowed (Sprint 3 update; preserved verbatim shape)

- "TOCTOU eliminated on the ALLOW path."
  Reason: Φ_A reduces C₁ to within-Π; it does not eliminate it. Audit-record
  fidelity may still misreport the τ₀ realpath when the kernel ran a
  τ₁-resolved different element of Π.

- "Audit trail is integrity-protected."
  Reason: the Auditor-A Sprint 2 finding (child can write to fd 2 and forge
  records) is unaffected by Φ_A. Φ_A is an exec underlay, not an audit-stream
  fix.

- "Supervisor cannot be killed by the supervised child."
  Reason: same — Φ_A doesn't change PID-namespace or signal sharing.

- "Production-grade exec guard."
  Reason: this lab is a mechanism proof on a controlled host. Production-grade
  requires PID-namespace separation, audit-stream integrity, in-process
  SHA256, JSON-parser hardening, and the operator surface for policy
  templating, none of which Sprint 3 ships.

---

## R₆ [claim_if_failed]

K_failure (assertable iff Φ_A is abandoned per the stop conditions in R₄ and
the sprint terminates with Φ_E only):

> "On this host (Ubuntu 24.04.1, kernel Linux 6.17.0-14-generic), Sprint 3
> attempted to install a Landlock `LANDLOCK_ACCESS_FS_EXECUTE` underlay
> beneath the existing Sprint 2 `SECCOMP_RET_USER_NOTIF` supervisor and
> abandoned the attempt because <recorded reason: kernel ABI mismatch /
> loader-read scope unbounded / >2 harness regressions>. Sprint 3 therefore
> ships zero new mechanism: Γ is byte-identical to the Sprint 2 binary
> (sha256 anchored), the policy file is byte-identical to
> `policy/sprint2.allow.json`, the harness `scripts/replay_sprint2_identity.sh`
> reproduces `pass=12 fail=0` on independent re-run. The Sprint 2 caveat C₁
> (path-based F_CONT TOCTOU on the ALLOW path) is restated unchanged: the
> supervisor validates `(realpath, st_dev, st_ino)` at τ₀; the kernel re-reads
> the path argument from child userspace at τ₁ to perform the actual execve;
> ∃ adversary in Σ_c who wins the τ₀–τ₁ window can cause the kernel to exec
> an object distinct from the supervisor-validated one. This residual is
> kernel-documented (`man 2 seccomp_unotify`, 'TOCTOU considerations') and is
> the reason the Sprint 2 claim shape stops at 'mechanism proof' rather than
> 'security boundary'. Sprint 3 does not change that boundary; it documents
> why the operator Φ_A could not be shipped this sprint and what the next
> sprint must answer to retry."

This Φ_E claim is materially different from Φ_E-as-comfort: it is gated
behind a sprint-level *attempt* at Φ_A and includes the recorded failure
reason. The Sprint 2 discipline observation in both Auditor reviews
("preserve failed runs verbatim") applies to Φ_E here: the abandoned-Φ_A
artifacts must remain in `proofs/sprint3_runs/`, not be deleted.

---

## R₇ [do_not]

### do_not_broaden

- OpenHands integration: `∂Σ_expand = ∅`. Sprint 3 does not touch OpenHands.
  Both Sprint 2 auditors flagged that OpenHands work is misordered ahead of
  Sprint 2's own audit-stream and supervisor-PID-namespace findings.
- Docker integration: Sprint 3 does not run Γ inside a Docker container, does
  not produce a Dockerfile, does not add `docker run` to the harness. Adding
  a container layer over a Γ that still has the audit-forgery and
  killable-supervisor caveats *makes the demo worse* because reviewers will
  assume the container shoulders integrity weight Γ doesn't carry. Same
  reasoning applies to OpenHands.
- closure_detector_layer: out of scope. The policy-confusion findings A's
  Sprint 2 review surfaced (parser walks past string-valued
  `allowed_executables` to next array) are real and worth fixing, but they
  are *Sprint 2 prerequisites*, not Sprint 3 fix-path operators. They
  belong in a parallel cleanup task, not here.

### do_not_claim

For every K considered for the Sprint 3 memo, K is assertable iff K is proven
by ℛ or by an artifact equivalent in shape (live command output captured in
`proofs/sprint3_runs/`, SHAs anchored, replay script idempotent).

The following K are explicitly NOT assertable from Sprint 3 — no matter how
clean the Φ_A implementation lands:

- "Sprint 3 closes the F_CONT TOCTOU." (False; Φ_A bounds the residual to
  within-Π.)
- "Sprint 3 makes the audit trail integrity-protected." (False; Φ_A is
  unrelated to audit-stream design. Auditor A's Sprint 2 Critical Finding 1
  remains open.)
- "Sprint 3 makes Γ a security boundary." (False; one Sprint of one new
  kernel layer does not promote a mechanism proof to a security boundary.)
- "Sprint 3 ships production-ready exec guard." (False; production-ready
  requires PID-namespace separation, audit-stream isolation, in-process
  SHA256, JSON-parser hardening, and an operator surface for policy
  authoring, none of which Sprint 3 ships under Φ_A.)

If the Sprint 3 self-audit is tempted to assert any of the above, the
honest_claim_policy from invariant `[I6]` requires that the assertion be
withheld and instead added to the "Claims Still Not Allowed" list. The
Sprint 1 and Sprint 2 operator has a clean track record on this discipline;
preserve it.

### do_not_import

- governance_IP: out of scope. Sprint 3 must not pull policy-language
  schemas, claim-detector code, or governance taxonomies from any other lab
  in this user's tree. The policy file format remains the simple
  `allowed_executables` JSON shape Sprint 2 introduced. If JSON-parser
  hardening is desired (Sprint 2 audit Secondary Finding 2), use a
  permissively-licensed third-party single-header (jsmn, json-c) — not
  governance IP.
- closure_detector_layer: see do_not_broaden.

### do_not_rewrite

- Γ_architecture: do not rewrite Γ as a multi-process tracer, multi-namespace
  sandbox, or systemd-style exec wrapper. The current Γ shape (single
  supervisor + single supervised child + Unix-socket fd handoff +
  SECCOMP_RET_USER_NOTIF) is still the right shape for Φ_A. Φ_A inserts
  one new function call in the child branch; it does not require an
  architecture change.
- The condition for architecture rewrite is `∀ Φ ∈ {A..D} = infeasible`. On
  this host, **Φ_A and Φ_B.1 are both feasible (probed live).** The
  architecture-rewrite gate is not satisfied. Do not pre-emptively rewrite
  Γ "for future flexibility"; that is the kind of scope-bloat Auditor A
  flagged in the Sprint 2 review (the policy parser is a separate Secondary
  Finding precisely because it is the *only* place worth a rewrite, and
  even there, jsmn replaces strstr without a Γ architecture change).

---

## Discipline Notes (worth preserving from Sprint 2 reviews)

The operator's pattern of preserving failed runs (e.g.
`proofs/sprint2_runs/sprint2-20260430T220518Z` with `pass=10 fail=2`),
SHA-anchoring source and binary in every replay, expanding the "Claims Still
Not Allowed" list as new abilities are gained, and naming residual TOCTOU
honestly *in the same memo as the PASS verdict* is the actual differentiator
of this audit chain. Sprint 3 must continue this pattern: ship the Φ_A
attempt (or the Φ_E fallback), preserve every failed harness run verbatim,
and grow the Claims Still Not Allowed list at least one item richer than
Sprint 2 (Φ_A residual: within-Π audit fidelity).

---

## Files

- This analysis: `proofs/SPRINT3_FIX_PATH_ANALYSIS_B_20260430.md`
- Parallel Auditor A analysis: `proofs/SPRINT3_FIX_PATH_ANALYSIS_A_20260430.md` (expected)
- Sprint 2 source of record:
  - `guard/usernotify_exec_guard.c` (672 lines, sha256 `58b8409d…`)
  - `bin/usernotify_exec_guard` (sha256 `40e156ab…`)
  - `policy/sprint2.allow.json`
  - `scripts/replay_sprint2_identity.sh`
  - `proofs/SPRINT2_*.md`
  - `proofs/AUDIT_20260430_sprint2_independent_review_a.md`
  - `proofs/AUDIT_20260430_sprint2_independent_review_b.md`
- Reference Ω_ref:
  `/home/blazingradar/boundr-adversarial-gaming-lab/kernel_sidecar/harness/seccomp_openat_write_demo_v0.c`
- Host kernel: `Linux loftingWonder 6.17.0-14-generic #14~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC`
- Host Landlock: ABI v7 (`/usr/include/linux/landlock.h`, runtime-probed)
- Host SECCOMP ADDFD: present and functional with O_RDONLY srcfd (probed)
