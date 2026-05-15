# Sprint 4 — Subagent Audit Review (Maxwell)

Date: 2026-04-30
Auditor: Maxwell (`019de0b9-2dd0-7fe1-9ee5-b2be8c59c147`)
Posture: read-only proof quality, audit-integrity, and review-readiness audit.
Scope: `scripts/replay_sprint4_audit_integrity.sh`, `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md`, `proofs/SPRINT4_COMMAND_LOG_20260430.md`, preserved failed run `proofs/sprint4_runs/sprint4-20260430T232423Z`, corrected run `proofs/sprint4_runs/sprint4-20260430T232441Z`, Sprint 2 replay, compiler/analyzer cleanliness, hashes, and claim boundaries.

## Findings

Medium: The F2 "closed for SIGTERM/INT/HUP" claim is a little too broad. The preserved proof shows the reproduced SIGTERM path works, but the handler uses `snprintf` inside a signal handler, which is not async-signal-safe: `guard/usernotify_exec_guard.c:95`. The report does caveat "denial-of-service, not survival," but line 12 still reads broader than the implementation can reliably promise: `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md:12`. Reviewer-facing framing should say "reproduced SIGTERM/INT/HUP-style supervisor termination now emits a best-effort final record," unless the handler is made strictly async-signal-safe.

Low: The F6 replay check is weaker than the claim. The script only greps for the literal string `sha256sum`: `scripts/replay_sprint4_audit_integrity.sh:143`. That supports "no longer references `sha256sum`," but it does not by itself prove "SHA256 is computed in-process via AF_ALG" as stated in the report: `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md:16`. The source does contain AF_ALG use, but the replay proof should not be treated as a behavioral proof of no external helper execution.

Low: The corrected run's `sha256s.txt` only binds the guard source and binary, while the report also records script hashes. The script writes only `$SRC` and `$GUARD`: `scripts/replay_sprint4_audit_integrity.sh:156`, and the run artifact confirms only two entries: `proofs/sprint4_runs/sprint4-20260430T232441Z/sha256s.txt:1`. The report's four hashes match the current tree, but two of them are not captured by the run artifact itself: `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md:99`.

## Verified

Sprint 4 corrected run is `pass=14 fail=0`: `proofs/sprint4_runs/sprint4-20260430T232441Z/replay_summary.txt:17`.

The preserved failed run is honestly retained as `pass=13 fail=1`, failing only the old `/proc/self/exe` expectation: `proofs/sprint4_runs/sprint4-20260430T232423Z/replay_summary.txt:13`.

Sprint 2 replay after Sprint 4 is `pass=12 fail=0`: `proofs/sprint2_runs/sprint2-20260430T232453Z/replay_summary.txt:15`.

Compiler cleanliness is supported by empty Sprint 4 `compile.stdout`/`compile.stderr`, and the auditor also ran:

```bash
gcc -Wall -Wextra -fanalyzer -O2 -fsyntax-only guard/usernotify_exec_guard.c
```

It emitted no diagnostics.

The main audit-integrity claims are legible and mostly well-scoped. The report correctly preserves major caveats around Docker/OpenHands, production sandboxing, `F_CONT` TOCTOU, DoS, schema-specific parsing, AF_ALG portability, and execute-only scope: `proofs/SPRINT4_AUDIT_INTEGRITY_HARDENING_20260430.md:109`.

## Review Readiness

review-ready for a Sprint 4 evidence review, with the F2 wording tightened. Do not call it production-ready or Docker/OpenHands-ready, and the document itself does not overclaim that.

The strongest statement it can honestly support is:

> Sprint 4 closes the reproduced audit-forgery and identity-regression issues, preserves Sprint 2 replay behavior, and leaves integration proof plus known TOCTOU architecture work for later.
