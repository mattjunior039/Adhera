from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python scripts/validate_rxnorm_local.py <path-to-rxnorm-json>")
        return 2

    path = Path(sys.argv[1]).expanduser().resolve()
    if not path.exists() or not path.is_file():
        print(f"ERROR: file not found: {path}")
        return 1

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"ERROR: invalid JSON: {exc}")
        return 1

    if not isinstance(payload, list):
        print("ERROR: expected top-level JSON array")
        return 1

    total = len(payload)
    valid = 0
    missing_name = 0
    non_string_name = 0

    for item in payload:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        if name is None:
            missing_name += 1
            continue
        if not isinstance(name, str):
            non_string_name += 1
            continue
        if not name.strip():
            missing_name += 1
            continue
        valid += 1

    print(f"file: {path}")
    print(f"rows: {total}")
    print(f"valid-name-rows: {valid}")
    print(f"missing-name-rows: {missing_name}")
    print(f"non-string-name-rows: {non_string_name}")

    if valid == 0:
        print("ERROR: no valid rows found")
        return 1

    print("OK: dataset is usable for local RxNorm lookup")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
