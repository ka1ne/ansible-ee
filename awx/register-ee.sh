#!/usr/bin/env bash
# awx/register-ee.sh
#
# Creates or updates the custom EE definition in AWX via the API.
# Used by both 'make awx-sync-ee' (local) and the Harness ee-build pipeline.
#
# Required env vars:
#   AWX_HOST      — e.g. http://localhost:30080 or https://awx.ka1ne.dev
#   AWX_TOKEN     — AWX personal access token or service account token
#   EE_IMAGE      — full image ref including tag
#                   e.g. ghcr.io/ka1ne/ansible-ee:abc1234
#
# Optional:
#   EE_NAME       — display name in AWX (default: "Ansible EE")
#   REGISTRY_CRED — AWX credential name for the internal registry
#                   (default: "Internal Registry" — must already exist in AWX)

set -euo pipefail

AWX_HOST="${AWX_HOST:?AWX_HOST is required}"
AWX_TOKEN="${AWX_TOKEN:?AWX_TOKEN is required}"
EE_IMAGE="${EE_IMAGE:?EE_IMAGE is required}"
EE_NAME="${EE_NAME:-Ansible EE}"
REGISTRY_CRED="${REGISTRY_CRED:-Internal Registry}"

AUTH=(-H "Authorization: Bearer ${AWX_TOKEN}" -H "Content-Type: application/json")

echo "AWX host  : ${AWX_HOST}"
echo "EE image  : ${EE_IMAGE}"
echo "EE name   : ${EE_NAME}"

# -- Resolve registry credential ID ------------------------------------------
CRED_ID=$(
  EE_CRED_NAME="$REGISTRY_CRED" python3 - <<'EOF'
import os, sys, json, urllib.parse, urllib.request

host  = os.environ["AWX_HOST"]
token = os.environ["AWX_TOKEN"]
name  = os.environ["EE_CRED_NAME"]

req = urllib.request.Request(
  f"{host}/api/v2/credentials/?name={urllib.parse.quote(name)}",
  headers={"Authorization": f"Bearer {token}"}
)
d = json.load(urllib.request.urlopen(req))
print(d["results"][0]["id"] if d["count"] else "")
EOF
)

if [[ -z "$CRED_ID" ]]; then
  echo "WARN: registry credential '${REGISTRY_CRED}' not found in AWX — EE will be created without pull credential"
  CRED_PAYLOAD="null"
else
  echo "Registry credential ID: ${CRED_ID}"
  CRED_PAYLOAD="${CRED_ID}"
fi

# -- Check if EE already exists -----------------------------------------------
EE_ID=$(
  EE_LOOKUP_NAME="$EE_NAME" python3 - <<'EOF'
import os, sys, json, urllib.parse, urllib.request

host  = os.environ["AWX_HOST"]
token = os.environ["AWX_TOKEN"]
name  = os.environ["EE_LOOKUP_NAME"]

req = urllib.request.Request(
  f"{host}/api/v2/execution_environments/?name={urllib.parse.quote(name)}",
  headers={"Authorization": f"Bearer {token}"}
)
d = json.load(urllib.request.urlopen(req))
print(d["results"][0]["id"] if d["count"] else "")
EOF
)

PAYLOAD=$(
  EE_CRED_PAYLOAD="$CRED_PAYLOAD" python3 - <<'EOF'
import os, json

d = {
  "name":  os.environ["EE_NAME"],
  "image": os.environ["EE_IMAGE"],
  "pull":  "always"
}
cred = os.environ["EE_CRED_PAYLOAD"]
if cred != "null":
    d["credential"] = int(cred)
print(json.dumps(d))
EOF
)

if [[ -n "$EE_ID" ]]; then
  echo "Updating EE (id=${EE_ID}) ..."
  curl -sf -X PATCH "${AUTH[@]}" -d "$PAYLOAD" \
    "${AWX_HOST}/api/v2/execution_environments/${EE_ID}/" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Updated: {d[\"name\"]} -> {d[\"image\"]}')"
else
  echo "Creating EE ..."
  curl -sf -X POST "${AUTH[@]}" -d "$PAYLOAD" \
    "${AWX_HOST}/api/v2/execution_environments/" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Created: id={d[\"id\"]} name={d[\"name\"]} image={d[\"image\"]}')"
fi

echo "AWX EE sync complete."
