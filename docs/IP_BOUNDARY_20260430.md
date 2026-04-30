# IP Boundary

Date: 2026-04-30

## Public Demo Should Expose

The public demo can expose:

- a minimal seccomp profile or equivalent runtime boundary
- a thin user-notify handler or simple policy checker
- a small hand-written `policy.json`
- basic JSON block logs
- a small set of attack/allow cases
- OpenHands or raw Docker integration instructions
- a video-ready reproduction

These are demonstration artifacts, not the full governance system.

## Private Work To Protect

The genuinely valuable lab work should remain private unless deliberately released later.

### 1. Frozen Evidence Packet Discipline

Not just logs. The private value is the methodology for creating and validating structured, timestamped, reproducible decision records:

- call ledgers
- unreconciled reserved calls
- frozen semantic point hashes
- run manifests
- watcher audits
- post-run audits

The public demo only needs a basic audit log.

### 2. Contamination Detection Methodology

The private value is the diagnostic discipline:

> rule out the pipeline before blaming the model

Example: identifying timestamp or input contamination as the cause of verdict drift instead of misattributing variance to the model.

The public seccomp demo does not need this.

### 3. Authority Composition Architecture

The private value is the multi-seat governance architecture:

- deterministic gate
- constrained LLM seat
- free-form LLM seat
- disagreement preserved rather than averaged away

The public demo should not expose this architecture beyond a high-level mention that broader private governance work exists.

### 4. ATS / IR / Compilation Layer

The private value includes:

- canonical IR
- typed ambiguity fields
- salted tokenizer concepts
- bounded-task compilation layer
- local-model substitution methodology

The seccomp demo should use a hand-written policy, not policy generation.

### 5. Typed Fail-Closed Refusal System

The private value is the refusal and classification taxonomy:

- typed reason codes
- fail-closed semantics
- structured ambiguity handling
- higher-level operator normalization

The public demo can use simple reasons like `blocked_executable` or `outside_policy`.

## Public README Boundary Sentence

Use a sentence like this if the repo ships:

> This is a minimal guard derived from a larger private lab system for deterministic policy adjudication, frozen audit packets, and drift detection across agent execution. The minimal version shipped here is sufficient for the OpenHands integration; the broader system remains private lab work.

## Prior-Work Protection

If this becomes public:

- date-stamp the public repository
- keep private lab commits and frozen artifacts intact
- preserve local run logs
- write a dated threat-model note before posting
- do not imply the public repo is the full system

The goal is to be first and citable without giving away the private methodology.
