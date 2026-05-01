# Failed Probe Harness Attempt

This run is preserved because the first post-audit probe wrapper was too weak.

The generator produced the expected YAML shape, but the inline Python assertion
treated `observed_identity_evidence` as a map instead of the list the generator
emits. The assertion failed with `TypeError`, while the surrounding shell command
continued and wrote an incorrect pass summary.

The corrected rerun used `set -euo pipefail`, fixed the assertion to match the
actual YAML shape, and passed at:

`proofs/sprint10_runs/sprint10-post-audit-probes-20260501T132858Z`
