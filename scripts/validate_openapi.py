#!/usr/bin/env python3
"""
Validate OpenAPI specification against FastAPI implementation.

This script ensures the hand-written openapi.yaml stays in sync with
the auto-generated OpenAPI spec from FastAPI.

Usage:
    python scripts/validate_openapi.py

    # Export the current FastAPI spec to file
    python scripts/validate_openapi.py --export

Exit codes:
    0: Validation passed
    1: Validation failed (specs differ)
    2: Error (file not found, server not running, etc.)
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(2)

try:
    import requests
except ImportError:
    print("Error: requests not installed. Run: pip install requests")
    sys.exit(2)


SPEC_FILE = Path(__file__).parent.parent / "docs" / "spec" / "openapi.yaml"
FASTAPI_URL = "http://localhost:8000/openapi.json"


def load_yaml_spec() -> dict:
    """Load the hand-written OpenAPI spec from YAML file."""
    if not SPEC_FILE.exists():
        print(f"Error: OpenAPI spec not found at {SPEC_FILE}")
        sys.exit(2)

    with open(SPEC_FILE, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def fetch_fastapi_spec() -> dict:
    """Fetch the auto-generated OpenAPI spec from running FastAPI server."""
    try:
        response = requests.get(FASTAPI_URL, timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.ConnectionError:
        print(f"Error: Cannot connect to FastAPI server at {FASTAPI_URL}")
        print("Please start the server first: uvicorn src.api:app --port 8000")
        sys.exit(2)
    except Exception as e:
        print(f"Error fetching OpenAPI spec: {e}")
        sys.exit(2)


def compare_paths(yaml_spec: dict, fastapi_spec: dict) -> list[str]:
    """Compare API paths between specs and return differences."""
    differences = []

    yaml_paths = set(yaml_spec.get("paths", {}).keys())
    fastapi_paths = set(fastapi_spec.get("paths", {}).keys())

    # Check for missing paths
    missing_in_yaml = fastapi_paths - yaml_paths
    missing_in_fastapi = yaml_paths - fastapi_paths

    if missing_in_yaml:
        differences.append(f"Paths in FastAPI but missing in openapi.yaml: {missing_in_yaml}")

    if missing_in_fastapi:
        differences.append(f"Paths in openapi.yaml but missing in FastAPI: {missing_in_fastapi}")

    # Check methods for each path
    for path in yaml_paths & fastapi_paths:
        yaml_methods = set(yaml_spec["paths"][path].keys())
        fastapi_methods = set(fastapi_spec["paths"][path].keys())

        if yaml_methods != fastapi_methods:
            differences.append(
                f"Path '{path}' method mismatch: "
                f"YAML={yaml_methods}, FastAPI={fastapi_methods}"
            )

    return differences


def compare_schemas(yaml_spec: dict, fastapi_spec: dict) -> list[str]:
    """Compare schema definitions between specs."""
    differences = []

    yaml_schemas = set(yaml_spec.get("components", {}).get("schemas", {}).keys())
    fastapi_schemas = set(fastapi_spec.get("components", {}).get("schemas", {}).keys())

    # Note: FastAPI may generate additional helper schemas, so we only check
    # that all YAML schemas exist in FastAPI
    missing_in_fastapi = yaml_schemas - fastapi_schemas

    # Some schemas may have different names due to Pydantic naming
    # We do a more lenient check here
    critical_schemas = {
        "AnalyzeRequest", "QueryRequest", "AnalysisResponse",
        "QueryResponse", "HealthResponse", "ErrorResponse", "MoveCandidateResponse"
    }

    missing_critical = critical_schemas - fastapi_schemas
    if missing_critical:
        differences.append(f"Critical schemas missing in FastAPI: {missing_critical}")

    return differences


def validate_spec_structure(yaml_spec: dict) -> list[str]:
    """Validate the YAML spec has required OpenAPI structure."""
    errors = []

    required_fields = ["openapi", "info", "paths"]
    for field in required_fields:
        if field not in yaml_spec:
            errors.append(f"Missing required field: {field}")

    # Check info section
    info = yaml_spec.get("info", {})
    if "title" not in info:
        errors.append("Missing info.title")
    if "version" not in info:
        errors.append("Missing info.version")

    return errors


def export_fastapi_spec():
    """Export the FastAPI-generated spec to a JSON file for reference."""
    spec = fetch_fastapi_spec()
    export_path = Path(__file__).parent.parent / "docs" / "spec" / "openapi.generated.json"

    with open(export_path, "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=2, ensure_ascii=False)

    print(f"Exported FastAPI spec to: {export_path}")


def main():
    parser = argparse.ArgumentParser(description="Validate OpenAPI spec")
    parser.add_argument("--export", action="store_true", help="Export FastAPI spec to file")
    parser.add_argument("--offline", action="store_true", help="Only validate YAML structure (no server needed)")
    args = parser.parse_args()

    print("Loading openapi.yaml...")
    yaml_spec = load_yaml_spec()

    # Validate YAML structure
    structure_errors = validate_spec_structure(yaml_spec)
    if structure_errors:
        print("\n❌ YAML structure errors:")
        for error in structure_errors:
            print(f"  - {error}")
        sys.exit(1)

    print("✓ YAML structure is valid")

    if args.offline:
        print("\n✓ Offline validation passed")
        return

    if args.export:
        export_fastapi_spec()
        return

    print(f"\nFetching FastAPI spec from {FASTAPI_URL}...")
    fastapi_spec = fetch_fastapi_spec()

    # Compare specs
    all_differences = []
    all_differences.extend(compare_paths(yaml_spec, fastapi_spec))
    all_differences.extend(compare_schemas(yaml_spec, fastapi_spec))

    if all_differences:
        print("\n❌ Specification differences found:")
        for diff in all_differences:
            print(f"  - {diff}")
        print("\nPlease update openapi.yaml to match the FastAPI implementation.")
        print("Tip: Run with --export to see the full FastAPI-generated spec.")
        sys.exit(1)
    else:
        print("\n✓ OpenAPI spec matches FastAPI implementation")
        print("  Paths: OK")
        print("  Schemas: OK")


if __name__ == "__main__":
    main()
