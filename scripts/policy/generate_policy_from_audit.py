#!/usr/bin/env python3
import argparse
import json
import os
import sys
from pathlib import Path

import yaml


def iter_json_lines(path: Path):
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line or not line.startswith("{"):
                continue
            try:
                yield line_no, json.loads(line)
            except json.JSONDecodeError:
                continue


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate reviewable YAML policy from guard audit JSON logs."
    )
    parser.add_argument("audit_log", type=Path)
    parser.add_argument("output_yaml", type=Path)
    parser.add_argument(
        "--policy-id",
        default="observed_openhands_policy_v1",
        help="policy_id to write into generated YAML.",
    )
    parser.add_argument(
        "--include-blocked-summary",
        type=Path,
        help="Optional JSON path for observed BLOCK records.",
    )
    parser.add_argument(
        "--trusted-root",
        type=Path,
        help="Require audit_log to resolve under this directory.",
    )
    parser.add_argument(
        "--require-policy-id",
        action="append",
        default=[],
        help=(
            "Require all exec_decision records with policy_id to match one of these "
            "values. May be supplied more than once."
        ),
    )
    args = parser.parse_args()

    if not args.audit_log.is_file():
        print(f"audit log not found: {args.audit_log}", file=sys.stderr)
        return 2
    if args.trusted_root:
        try:
            audit_real = args.audit_log.resolve()
            root_real = args.trusted_root.resolve()
            os.path.commonpath([str(audit_real), str(root_real)])
        except (OSError, ValueError) as exc:
            print(f"cannot validate trusted root: {exc}", file=sys.stderr)
            return 2
        if os.path.commonpath([str(audit_real), str(root_real)]) != str(root_real):
            print(f"audit log is outside trusted root: {args.audit_log}", file=sys.stderr)
            return 2

    allowed: dict[str, dict] = {}
    blocked: list[dict] = []
    blocked_realpaths: set[str] = set()
    policy_ids: set[str] = set()
    total_exec_decisions = 0

    for line_no, obj in iter_json_lines(args.audit_log):
        if obj.get("event") != "exec_decision":
            continue
        total_exec_decisions += 1
        policy_id = obj.get("policy_id")
        if isinstance(policy_id, str):
            policy_ids.add(policy_id)
            if args.require_policy_id and policy_id not in set(args.require_policy_id):
                print(
                    f"policy_id mismatch at line {line_no}: {policy_id}",
                    file=sys.stderr,
                )
                return 2
        decision = obj.get("decision")
        realpath = obj.get("realpath")
        if decision == "ALLOW" and isinstance(realpath, str) and realpath.startswith("/"):
            entry = allowed.setdefault(
                realpath,
                {
                    "realpath": realpath,
                    "first_line": line_no,
                    "last_line": line_no,
                    "observations": 0,
                    "raw_exe": obj.get("raw_exe"),
                    "sha256": obj.get("sha256"),
                    "dev": obj.get("dev"),
                    "ino": obj.get("ino"),
                },
            )
            entry["last_line"] = line_no
            entry["observations"] += 1
        elif decision == "BLOCK":
            if isinstance(realpath, str) and realpath.startswith("/"):
                blocked_realpaths.add(realpath)
            blocked.append(
                {
                    "line": line_no,
                    "raw_exe": obj.get("raw_exe"),
                    "realpath": obj.get("realpath"),
                    "reason": obj.get("reason"),
                    "sha256": obj.get("sha256"),
                }
            )

    if not allowed:
        print("no ALLOW exec_decision records found", file=sys.stderr)
        return 1

    overlap_excluded = sorted(set(allowed) & blocked_realpaths)
    for realpath in overlap_excluded:
        allowed.pop(realpath, None)

    if not allowed:
        print("all ALLOW realpaths overlapped with BLOCK records", file=sys.stderr)
        return 1

    payload = {
        "policy_id": args.policy_id,
        "metadata": {
            "generated_from": str(args.audit_log),
            "total_exec_decisions": total_exec_decisions,
            "observed_allowed_count": len(allowed),
            "observed_blocked_count": len(blocked),
            "source_policy_ids": sorted(policy_ids),
            "blocked_overlap_excluded_count": len(overlap_excluded),
            "blocked_overlap_excluded": overlap_excluded,
            "review_required": True,
            "note": (
                "Generated from observed ALLOW records. Review before enforcing; "
                "any realpath also seen in a BLOCK record is excluded from "
                "allowed_executables."
            ),
        },
        "observed_identity_evidence": [allowed[path] for path in sorted(allowed)],
        "allowed_executables": sorted(allowed),
    }

    args.output_yaml.parent.mkdir(parents=True, exist_ok=True)
    args.output_yaml.write_text(
        "# Generated from guard audit logs. Review before enforcing.\n"
        + yaml.safe_dump(payload, sort_keys=False),
        encoding="utf-8",
    )

    if args.include_blocked_summary:
        args.include_blocked_summary.parent.mkdir(parents=True, exist_ok=True)
        args.include_blocked_summary.write_text(
            json.dumps(
                {
                    "audit_log": str(args.audit_log),
                    "blocked_count": len(blocked),
                    "blocked": blocked,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    print(
        json.dumps(
            {
                "audit_log": str(args.audit_log),
                "output_yaml": str(args.output_yaml),
                    "policy_id": args.policy_id,
                    "allowed_executables": len(allowed),
                    "blocked_records": len(blocked),
                    "blocked_overlap_excluded": len(overlap_excluded),
                    "total_exec_decisions": total_exec_decisions,
                },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
