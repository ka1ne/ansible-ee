#!/usr/bin/env python3
"""
Validate a deployment manifest YAML against the JSON schema.
Used in pipeline Stage 1 before Ansible execution.

Usage:
  python scripts/validate-manifest.py manifest.yml
  python scripts/validate-manifest.py manifest.yml --schema schemas/manifest-schema.json
"""
import json
import sys
from pathlib import Path

try:
    import jsonschema
    import yaml
except ImportError:
    print("ERROR: Install deps: pip install jsonschema pyyaml", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <manifest.yml> [--schema <schema.json>]", file=sys.stderr)
        sys.exit(1)

    manifest_path = Path(sys.argv[1])
    schema_path = Path(sys.argv[3] if "--schema" in sys.argv else "schemas/manifest-schema.json")

    if not manifest_path.exists():
        print(f"ERROR: Manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)

    if not schema_path.exists():
        print(f"ERROR: Schema not found: {schema_path}", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = yaml.safe_load(f)

    with open(schema_path) as f:
        schema = json.load(f)

    try:
        jsonschema.validate(instance=manifest, schema=schema)
        print(f"OK: Manifest is valid")
        print(f"  Environment: {manifest.get('env')}")
        print(f"  Capabilities: {', '.join(manifest.get('capabilities', []))}")
        print(f"  Targets: {manifest.get('target_hosts')}")
        print(f"  Change ID: {manifest.get('change_id', 'N/A')}")
    except jsonschema.ValidationError as e:
        print(f"FAIL: Manifest validation error: {e.message}", file=sys.stderr)
        print(f"  Path: {' → '.join(str(p) for p in e.absolute_path)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
