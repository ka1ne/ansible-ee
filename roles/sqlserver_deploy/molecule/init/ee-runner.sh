#!/usr/bin/env bash
# ee-runner.sh — Molecule EE shim
#
# Molecule calls ansible-playbook as:
#   <executable> [ansible-opts...] <playbook.yml>
#
# ansible-navigator expects:
#   ansible-navigator run <playbook.yml> [navigator-opts] -- [ansible-opts]
#
# This script splits off the last argument (the playbook) and rewrites
# the call accordingly.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "ee-runner.sh: no arguments passed" >&2
  exit 1
fi

PLAYBOOK="${*: -1}"
ANSIBLE_OPTS=("${@:1:$(( $# - 1 ))}")

exec ansible-navigator run "$PLAYBOOK" \
  --mode stdout \
  --execution-environment true \
  --eei "${EE_IMAGE:-ghcr.io/ka1ne/ansible-ee:latest}" \
  --pull-policy "${EE_PULL_POLICY:-missing}" \
  --container-engine podman \
  -- "${ANSIBLE_OPTS[@]}"
