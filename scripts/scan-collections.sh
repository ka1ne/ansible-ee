#!/usr/bin/env bash
set -euo pipefail

# scan-collections.sh
# Unpacks Galaxy collections and runs security scans on their contents.
# Intended to run in CI after ansible-builder resolves dependencies.
#
# Prerequisites: bandit, semgrep, ansible-lint, pip-audit (pip install)
# Usage: ./scripts/scan-collections.sh <collections-dir>

COLLECTIONS_DIR="${1:-/home/runner/.ansible/collections/ansible_collections}"
SCAN_RESULTS_DIR="${2:-/tmp/scan-results}"
EXIT_CODE=0

mkdir -p "${SCAN_RESULTS_DIR}"

echo "=== Ansible Collection Security Scan ==="
echo "Collections dir: ${COLLECTIONS_DIR}"
echo ""

# --- 1. Scan Python modules with bandit ---
echo "[1/4] Running bandit on collection Python code..."
if command -v bandit &>/dev/null; then
  find "${COLLECTIONS_DIR}" -name "*.py" -not -path "*/tests/*" \
    | xargs bandit -r -f json -o "${SCAN_RESULTS_DIR}/bandit-report.json" \
      --severity-level medium \
      --confidence-level medium \
    || EXIT_CODE=1
  echo "  → Report: ${SCAN_RESULTS_DIR}/bandit-report.json"
else
  echo "  → SKIP: bandit not installed"
fi

# --- 2. Scan with semgrep for common IaC issues ---
echo "[2/4] Running semgrep on collection code..."
if command -v semgrep &>/dev/null; then
  semgrep scan \
    --config "p/python" \
    --config "p/command-injection" \
    --json \
    --output "${SCAN_RESULTS_DIR}/semgrep-report.json" \
    "${COLLECTIONS_DIR}" \
    || EXIT_CODE=1
  echo "  → Report: ${SCAN_RESULTS_DIR}/semgrep-report.json"
else
  echo "  → SKIP: semgrep not installed"
fi

# --- 3. Extract and scan Python dependencies from collections ---
echo "[3/4] Scanning collection Python dependencies..."
COMBINED_REQS="${SCAN_RESULTS_DIR}/collection-python-reqs.txt"
: > "${COMBINED_REQS}"

find "${COLLECTIONS_DIR}" -name "requirements.txt" -exec cat {} + >> "${COMBINED_REQS}" 2>/dev/null || true
find "${COLLECTIONS_DIR}" -path "*/meta/ee-requirements.txt" -exec cat {} + >> "${COMBINED_REQS}" 2>/dev/null || true

if [ -s "${COMBINED_REQS}" ]; then
  sort -u -o "${COMBINED_REQS}" "${COMBINED_REQS}"
  echo "  Found $(wc -l < "${COMBINED_REQS}") unique Python deps across collections"

  if command -v pip-audit &>/dev/null; then
    pip-audit -r "${COMBINED_REQS}" \
      --format json \
      --output "${SCAN_RESULTS_DIR}/pip-audit-report.json" \
      || EXIT_CODE=1
    echo "  → Report: ${SCAN_RESULTS_DIR}/pip-audit-report.json"
  else
    echo "  → SKIP: pip-audit not installed"
  fi
else
  echo "  → No Python requirements found in collections"
fi

# --- 4. ansible-lint on collection roles/playbooks ---
echo "[4/4] Running ansible-lint on collection content..."
if command -v ansible-lint &>/dev/null; then
  find "${COLLECTIONS_DIR}" -name "*.yml" -path "*/roles/*" \
    | head -100 \
    | xargs ansible-lint \
      --format json \
      --output-file "${SCAN_RESULTS_DIR}/ansible-lint-report.json" \
      --strict \
    || EXIT_CODE=1
  echo "  → Report: ${SCAN_RESULTS_DIR}/ansible-lint-report.json"
else
  echo "  → SKIP: ansible-lint not installed"
fi

echo ""
echo "=== Scan Complete ==="
echo "Results in: ${SCAN_RESULTS_DIR}"
echo "Exit code: ${EXIT_CODE}"

exit "${EXIT_CODE}"
