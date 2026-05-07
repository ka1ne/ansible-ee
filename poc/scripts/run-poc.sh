#!/usr/bin/env bash
# poc/scripts/run-poc.sh
# Orchestrates the local WinRM + SQL Server 2022 PoC using Docker.
#
# PRE-REQUISITES (one-time setup):
#   1. Docker Desktop (or Docker in WSL2)
#   2. Enable WinRM on your Windows 11 host (run as Administrator in PowerShell):
#        Set-ExecutionPolicy RemoteSigned -Scope Process -Force
#        .\poc\scripts\setup-winrm-local.ps1
#   3. Copy poc/.env.example to poc/.env and set real credentials:
#        cp poc/.env.example poc/.env
#
# USAGE (from repo root):
#   bash poc/scripts/run-poc.sh [--skip-build]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POC_DIR="${REPO_ROOT}/poc"
ENV_FILE="${POC_DIR}/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[poc] $*${NC}"; }
ok()    { echo -e "${GREEN}[poc] $*${NC}"; }
fail()  { echo -e "${RED}[poc] $*${NC}" >&2; exit 1; }

SKIP_BUILD=false
for arg in "$@"; do
    [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
done

[[ -f "$ENV_FILE" ]] || fail "poc/.env not found — copy poc/.env.example to poc/.env and fill in values."
# shellcheck disable=SC2046
export $(grep -v '^#' "$ENV_FILE" | xargs)

: "${WINRM_USER:?WINRM_USER not set in .env}"
: "${WINRM_PASSWORD:?WINRM_PASSWORD not set in .env}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD not set in .env}"
MSSQL_HOST="${MSSQL_HOST:-127.0.0.1}"

NETWORK_NAME="poc-net"
MSSQL_CONTAINER="mssql"
MSSQL_IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
EE_IMAGE="ansible-ee:poc"
EE_CONTAINER="ansible-ee-poc"

cleanup() {
    info "Cleaning up containers..."
    docker rm -f "$MSSQL_CONTAINER" "$EE_CONTAINER" 2>/dev/null || true
    docker network rm -f "$NETWORK_NAME" 2>/dev/null || true
}
trap cleanup EXIT

info "Creating Docker network: $NETWORK_NAME"
docker network inspect "$NETWORK_NAME" &>/dev/null || docker network create "$NETWORK_NAME"

if [[ "$SKIP_BUILD" == "false" ]]; then
    info "Building Ansible EE image..."
    docker build -t "$EE_IMAGE" -f "${REPO_ROOT}/Dockerfile" "${REPO_ROOT}"
    ok "EE image built: $EE_IMAGE"
else
    info "Skipping build (--skip-build)"
fi

info "Starting SQL Server 2022 container ($MSSQL_CONTAINER)..."
docker run -d \
    --name "$MSSQL_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p 1433:1433 \
    -e ACCEPT_EULA=Y \
    -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
    -e MSSQL_PID=Developer \
    "$MSSQL_IMAGE"

info "Waiting for SQL Server to be ready (up to 60s)..."
for i in $(seq 1 12); do
    if docker exec "$MSSQL_CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
            -Q "SELECT 1" -No -l 5 &>/dev/null; then
        ok "SQL Server is ready."
        break
    fi
    [[ $i -eq 12 ]] && fail "SQL Server did not become ready in time."
    echo "  Attempt $i/12 — waiting 5s..."
    sleep 5
done

info "Running Ansible EE with winrm-poc.yml playbook..."
docker run --rm \
    --name "$EE_CONTAINER" \
    --network "$NETWORK_NAME" \
    --add-host "host.containers.internal:host-gateway" \
    -e WINRM_USER="$WINRM_USER" \
    -e WINRM_PASSWORD="$WINRM_PASSWORD" \
    -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
    -e MSSQL_HOST="$MSSQL_HOST" \
    -v "${REPO_ROOT}/poc/playbooks:/runner/poc/playbooks:ro" \
    -v "${REPO_ROOT}/poc/inventory:/runner/poc/inventory:ro" \
    "$EE_IMAGE" \
    ansible-playbook \
        -i /runner/poc/inventory/poc-local.yml \
        /runner/poc/playbooks/winrm-poc.yml \
        -v

ok "PoC complete."
