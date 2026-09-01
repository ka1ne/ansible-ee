#!/usr/bin/env bash
# dev/scripts/run-local.sh
#
# Runs the Windows connectivity probe against a real Windows host from a local
# Execution Environment container, with a throwaway SQL Server 2022 container
# standing in for a real database server.
#
# This is the fastest way to prove the EE, your credentials and the network
# path all work before involving AWX.
#
# One-time setup:
#   1. Docker (or Podman — export CONTAINER_RT=podman).
#   2. Enable WinRM on the Windows host, as Administrator:
#        Set-ExecutionPolicy RemoteSigned -Scope Process -Force
#        .\dev\scripts\setup-winrm-local.ps1
#   3. cp dev/.env.example .env   and fill in the values.
#
# Usage, from the repository root:
#   make test-local
#   bash dev/scripts/run-local.sh [--skip-build]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[local] $*${NC}"; }
ok()   { echo -e "${GREEN}[local] $*${NC}"; }
fail() { echo -e "${RED}[local] $*${NC}" >&2; exit 1; }

SKIP_BUILD=false
for arg in "$@"; do
    [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
done

[[ -f "$ENV_FILE" ]] || fail ".env not found — copy dev/.env.example to .env and fill it in."
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${WINRM_USER:?WINRM_USER is not set in .env}"
: "${WINRM_PASSWORD:?WINRM_PASSWORD is not set in .env}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD is not set in .env}"

# The address the WINDOWS host uses to reach SQL Server. Docker publishes 1433
# to the host, so the loopback address is right when SQL Server runs on the
# same machine you are targeting.
MSSQL_HOST="${MSSQL_HOST:-127.0.0.1}"

CONTAINER_RT="${CONTAINER_RT:-docker}"
NETWORK_NAME="ansible-ee-local"
MSSQL_CONTAINER="ansible-ee-mssql"
MSSQL_IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
EE_CONTAINER="ansible-ee-probe"
EE_IMAGE="${IMAGE_NAME:-ghcr.io/ka1ne/ansible-ee}:${IMAGE_TAG:-latest}"

cleanup() {
    info "Cleaning up containers"
    $CONTAINER_RT rm -f "$MSSQL_CONTAINER" "$EE_CONTAINER" >/dev/null 2>&1 || true
    $CONTAINER_RT network rm -f "$NETWORK_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

info "Ensuring network ${NETWORK_NAME} exists"
$CONTAINER_RT network inspect "$NETWORK_NAME" >/dev/null 2>&1 \
    || $CONTAINER_RT network create "$NETWORK_NAME" >/dev/null

if [[ "$SKIP_BUILD" == "false" ]]; then
    info "Building the Execution Environment"
    make -C "$REPO_ROOT" ee-build IMAGE_TAG="${IMAGE_TAG:-latest}"
    ok "Built ${EE_IMAGE}"
else
    info "Skipping build (--skip-build)"
fi

info "Starting SQL Server 2022"
$CONTAINER_RT run -d \
    --name "$MSSQL_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p 1433:1433 \
    -e ACCEPT_EULA=Y \
    -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
    -e MSSQL_PID=Developer \
    "$MSSQL_IMAGE" >/dev/null

info "Waiting for SQL Server to accept connections (up to 60s)"
for i in $(seq 1 12); do
    if $CONTAINER_RT exec "$MSSQL_CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" -No -l 5 >/dev/null 2>&1; then
        ok "SQL Server is ready"
        break
    fi
    [[ $i -eq 12 ]] && fail "SQL Server did not become ready in time."
    echo "  attempt ${i}/12 — waiting 5s"
    sleep 5
done

info "Running the connectivity probe through the EE"
$CONTAINER_RT run --rm \
    --name "$EE_CONTAINER" \
    --network "$NETWORK_NAME" \
    --add-host "host.containers.internal:host-gateway" \
    -e WINRM_HOST -e WINRM_USER -e WINRM_PASSWORD \
    -e MSSQL_HOST="$MSSQL_HOST" \
    -e MSSQL_SA_PASSWORD \
    -e ANSIBLE_STDOUT_CALLBACK=yaml \
    -v "${REPO_ROOT}/playbooks:/runner/playbooks:ro" \
    -v "${REPO_ROOT}/inventories:/runner/inventories:ro" \
    -v "${REPO_ROOT}/roles:/runner/roles:ro" \
    "$EE_IMAGE" \
    ansible-playbook \
        -i /runner/inventories/local/hosts.yml \
        /runner/playbooks/connectivity_probe.yml \
        -v

ok "Probe complete."
