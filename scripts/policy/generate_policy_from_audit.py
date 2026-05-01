#!/usr/bin/env python3
import argparse
import json
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
    args = parser.parse_args()

    if not args.audit_log.is_file():
        print(f"audit log not found: {args.audit_log}", file=sys.stderr)
        return 2

    allowed: dict[str, dict] = {}
    blocked: list[dict] = []
    total_exec_decisions = 0

    for line_no, obj in iter_json_lines(args.audit_log):
        if obj.get("event") != "exec_decision":
            continue
        total_exec_decisions += 1
        decision = obj.get("decision")
        realpath = obj.get("realpath")
        if decision == "ALLOW" and isinstance(realpath, str) and realpath.startswith("/"):
            allowed.setdefault(
                realpath,
                {
                    "realpath": realpath,
                    "first_line": line_no,
                    "raw_exe": obj.get("raw_exe"),
                    "sha256": obj.get("sha256"),
                    "dev": obj.get("dev"),
                    "ino": obj.get("ino"),
                },
            )
        elif decision == "BLOCK":
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

    payload = {
        "policy_id": args.policy_id,
        "metadata": {
            "generated_from": str(args.audit_log),
            "total_exec_decisions": total_exec_decisions,
            "observed_allowed_count": len(allowed),
            "observed_blocked_count": len(blocked),
            "review_required": True,
            "note": (
                "Generated from observed ALLOW records. Review before enforcing; "
                "blocked records are excluded from allowed_executables."
            ),
        },
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
                "total_exec_decisions": total_exec_decisions,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
