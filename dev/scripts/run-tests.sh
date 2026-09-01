#!/usr/bin/env bash
# dev/scripts/run-tests.sh
#
# Run the test suites against an existing Windows VM on your network.
#
# There is no provisioning here on purpose — you point it at a machine you
# already have, by IP or by name, and it does the rest.
#
#   bash dev/scripts/run-tests.sh --host 10.0.0.5 --user ansible
#   bash dev/scripts/run-tests.sh --host winlab01 --suite iis
#   make test-vm HOST=10.0.0.5 SUITE=mssql
#
# Each suite runs three phases:
#   converge      run the content and assert the result is what was asked for
#   idempotence   run it again and require that nothing changed
#   cleanup       remove everything the test created
#
# Credentials come from the environment or .env. Prefer that over --password,
# which is visible to anyone who can run `ps` on this machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[test] $*${NC}"; }
ok()   { echo -e "${GREEN}[test] $*${NC}"; }
warn() { echo -e "${YELLOW}[test] $*${NC}"; }
err()  { echo -e "${RED}[test] $*${NC}" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    cat <<'USAGE'
Run the test suites against an existing Windows VM on your network.

There is no provisioning here — you point it at a machine you already have,
by IP or by name, and it does the rest.

  bash dev/scripts/run-tests.sh --host 10.0.0.5 --user ansible
  bash dev/scripts/run-tests.sh --host winlab01 --suite iis
  make test-vm HOST=10.0.0.5 SUITE=mssql

Each suite runs three phases:
  converge      run the content and assert the result is what was asked for
  idempotence   run it again and require that nothing changed
  cleanup       remove everything the test created

Options:
  -H, --host ADDR        IP address or hostname of the Windows VM (required)
  -u, --user NAME        Account to authenticate as        (default: ansible)
  -p, --password PASS    Password. Prefer TEST_PASSWORD in the environment.
  -s, --suite NAME       connectivity | iis | mssql | all  (default: all)
      --transport NAME   ntlm | credssp | kerberos | basic (default: ntlm)
      --scheme NAME      http | https                      (default: http)
      --port N           WinRM port                        (default: 5985)
      --local            Run with the local ansible instead of the EE image
      --keep             Leave test artifacts on the VM for inspection
      --no-idempotence   Skip the second run
  -v, --verbose          Pass -vvv to ansible-playbook
  -h, --help             This message

Environment (all overridable by the flags above):
  TEST_HOST TEST_USER TEST_PASSWORD TEST_TRANSPORT TEST_SCHEME TEST_PORT
  TEST_IIS_PORT          Port the IIS test site listens on   (default: 18080)
  TEST_MSSQL_INSTANCE    SQL Server instance name    (default: MSSQLSERVER)
  TEST_MSSQL_PREREQS     true to let the role install SqlServerDsc/dbatools
USAGE
}

# .env first, so flags and existing environment win over it.
if [[ -f "${REPO_ROOT}/.env" ]]; then
    set -a; . "${REPO_ROOT}/.env"; set +a
fi

SUITE="all"
USE_EE=true
KEEP=false
IDEMPOTENCE=true
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -H|--host)       TEST_HOST="$2"; shift 2 ;;
        -u|--user)       TEST_USER="$2"; shift 2 ;;
        -p|--password)   TEST_PASSWORD="$2"; shift 2 ;;
        -s|--suite)      SUITE="$2"; shift 2 ;;
        --transport)     TEST_TRANSPORT="$2"; shift 2 ;;
        --scheme)        TEST_SCHEME="$2"; shift 2 ;;
        --port)          TEST_PORT="$2"; shift 2 ;;
        --local)         USE_EE=false; shift ;;
        --keep)          KEEP=true; shift ;;
        --no-idempotence) IDEMPOTENCE=false; shift ;;
        -v|--verbose)    VERBOSE="-vvv"; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               die "Unknown option: $1  (try --help)" ;;
    esac
done

: "${TEST_HOST:?--host is required (or set TEST_HOST)}"
: "${TEST_PASSWORD:?password is required — set TEST_PASSWORD in .env or the environment}"
export TEST_HOST TEST_PASSWORD
export TEST_USER="${TEST_USER:-ansible}"
export TEST_TRANSPORT="${TEST_TRANSPORT:-ntlm}"
export TEST_SCHEME="${TEST_SCHEME:-http}"
export TEST_PORT="${TEST_PORT:-5985}"
export TEST_IIS_PORT="${TEST_IIS_PORT:-18080}"
export TEST_MSSQL_INSTANCE="${TEST_MSSQL_INSTANCE:-MSSQLSERVER}"
export TEST_MSSQL_PREREQS="${TEST_MSSQL_PREREQS:-false}"

# Ties a run's created objects to that run, so parallel runs against the same VM
# cannot collide and a failed run leaves identifiable debris.
export TEST_RUN_ID="${TEST_RUN_ID:-$(date +%H%M%S)$$}"

case "$SUITE" in
    connectivity|iis|mssql) SUITES=("$SUITE") ;;
    all)                    SUITES=(connectivity iis mssql) ;;
    *) die "Unknown suite '$SUITE' — expected connectivity, iis, mssql or all" ;;
esac

CONTAINER_RT="${CONTAINER_RT:-docker}"
EE_IMAGE="${IMAGE_NAME:-ghcr.io/ka1ne/ansible-ee}:${IMAGE_TAG:-latest}"
INVENTORY="inventories/test/hosts.yml"

# Runs a playbook either in the EE image or with the local ansible. The EE path
# is the default because that is what AWX and Tekton actually run — a test that
# passes only against your laptop's ansible has not tested the thing you ship.
play() {
    local playbook="$1"
    if [[ "$USE_EE" == "true" ]]; then
        $CONTAINER_RT run --rm \
            -e TEST_HOST -e TEST_USER -e TEST_PASSWORD \
            -e TEST_TRANSPORT -e TEST_SCHEME -e TEST_PORT \
            -e TEST_RUN_ID -e TEST_IIS_PORT \
            -e TEST_MSSQL_INSTANCE -e TEST_MSSQL_PREREQS \
            -e ANSIBLE_STDOUT_CALLBACK=yaml \
            -v "${REPO_ROOT}:/runner:ro" \
            -w /runner \
            "$EE_IMAGE" \
            ansible-playbook -i "$INVENTORY" "$playbook" ${VERBOSE}
    else
        ( cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" "$playbook" ${VERBOSE} )
    fi
}

# True when the play recap reports no changes at all.
changed_nothing() {
    local output="$1"
    local total
    total=$(grep -oE 'changed=[0-9]+' <<<"$output" | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
    # No recap at all means the run never got far enough to report; treat that
    # as "not proven idempotent" rather than silently passing.
    grep -q 'changed=' <<<"$output" || total=1
    [[ "${total:-1}" -eq 0 ]]
}

FAILED=()
PASSED=()

for suite in "${SUITES[@]}"; do
    echo
    info "═══ suite: ${suite} ═══"
    converge="tests/${suite}.yml"
    cleanup="tests/${suite}_cleanup.yml"
    suite_ok=true

    info "converge — running the content and checking the result"
    if ! play "$converge"; then
        err "${suite}: converge failed"
        suite_ok=false
    fi

    # Connectivity makes no changes, so idempotence is meaningless for it.
    if [[ "$suite_ok" == "true" && "$IDEMPOTENCE" == "true" && "$suite" != "connectivity" ]]; then
        info "idempotence — running again, expecting no changes"
        if out=$(play "$converge" 2>&1); then
            echo "$out"
            if changed_nothing "$out"; then
                ok "${suite}: idempotent"
            else
                err "${suite}: NOT idempotent — the second run still reported changes"
                err "  This means the role reports work it did not need to do, which"
                err "  makes 'changed' meaningless to anyone watching a real run."
                suite_ok=false
            fi
        else
            echo "$out"
            err "${suite}: the second run failed outright"
            suite_ok=false
        fi
    fi

    if [[ -f "${REPO_ROOT}/${cleanup}" ]]; then
        if [[ "$KEEP" == "true" ]]; then
            warn "${suite}: --keep set, leaving artifacts behind (run id ${TEST_RUN_ID})"
        else
            info "cleanup — removing what the test created"
            play "$cleanup" || err "${suite}: CLEANUP FAILED — artifacts with id ${TEST_RUN_ID} may remain on ${TEST_HOST}"
        fi
    fi

    if [[ "$suite_ok" == "true" ]]; then PASSED+=("$suite"); else FAILED+=("$suite"); fi
done

echo
info "═══ summary — target ${TEST_HOST}, run id ${TEST_RUN_ID} ═══"
for s in "${PASSED[@]:-}"; do [[ -n "$s" ]] && ok    "  PASS  $s"; done
for s in "${FAILED[@]:-}"; do [[ -n "$s" ]] && err   "  FAIL  $s"; done

[[ ${#FAILED[@]} -eq 0 ]] || exit 1
ok "All suites passed."
