#!/usr/bin/env python3
import argparse
import json
import os
import sys
from pathlib import Path

import yaml


def fail(message: str) -> None:
    print(f"policy compile error: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_policy(path: Path) -> dict:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        fail(f"invalid YAML: {exc}")
    except OSError as exc:
        fail(f"cannot read {path}: {exc}")
    if not isinstance(data, dict):
        fail("top-level YAML value must be a mapping")
    return data


def validate_policy(data: dict, *, check_exists: bool) -> dict:
    policy_id = data.get("policy_id")
    if not isinstance(policy_id, str) or not policy_id.strip():
        fail("policy_id must be a non-empty string")

    allowed = data.get("allowed_executables")
    if not isinstance(allowed, list) or not allowed:
        fail("allowed_executables must be a non-empty list")

    normalized: list[str] = []
    seen: set[str] = set()
    for idx, item in enumerate(allowed):
        if not isinstance(item, str) or not item.strip():
            fail(f"allowed_executables[{idx}] must be a non-empty string")
        path = item.strip()
        if not path.startswith("/"):
            fail(f"allowed_executables[{idx}] must be an absolute path: {path}")
        if "\x00" in path:
            fail(f"allowed_executables[{idx}] contains NUL")
        if path in seen:
            fail(f"duplicate executable path: {path}")
        if check_exists and not os.path.isfile(path):
            fail(f"executable path does not exist on this host: {path}")
        if check_exists and not os.access(path, os.X_OK):
            fail(f"executable path is not executable on this host: {path}")
        seen.add(path)
        normalized.append(path)

    return {
        "policy_id": policy_id.strip(),
        "allowed_executables": normalized,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compile editable YAML policy to guard JSON policy."
    )
    parser.add_argument("input_yaml", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument(
        "--check-exists",
        action="store_true",
        help="Fail if allowed executable paths do not exist on this host.",
    )
    args = parser.parse_args()

    compiled = validate_policy(load_policy(args.input_yaml), check_exists=args.check_exists)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output_json.with_suffix(args.output_json.suffix + ".tmp")
    tmp.write_text(json.dumps(compiled, indent=2) + "\n", encoding="utf-8")
    tmp.replace(args.output_json)
    print(
        json.dumps(
            {
                "input": str(args.input_yaml),
                "output": str(args.output_json),
                "policy_id": compiled["policy_id"],
                "allowed_executables": len(compiled["allowed_executables"]),
                "check_exists": args.check_exists,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
