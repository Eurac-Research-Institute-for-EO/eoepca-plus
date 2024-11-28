#!/usr/bin/bash

ORIG_DIR="$(pwd)"
cd "$(dirname "$0")"
BIN_DIR="$(pwd)"

onExit() {
  cd "${ORIG_DIR}"
}
trap onExit EXIT

# Optional local .env file for secret values as env vars
source .env 2>/dev/null

SECRET_NAME="workspace-api-client"
NAMESPACE="workspace"

# Note: For now, the workspace API ingress uses the workspace-bb client by default.
WORKSPACE_API_CLIENT_ID="${2:-${WORKSPACE_API_CLIENT_ID:-workspace-bb}}"
WORKSPACE_API_CLIENT_PASSWORD="${2:-${WORKSPACE_API_CLIENT_PASSWORD:-changeme}}"

secretYaml() {
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="client_id=${WORKSPACE_API_CLIENT_ID}" \
    --from-literal="client_secret=${WORKSPACE_API_CLIENT_PASSWORD}" \
    --dry-run=client -o yaml
}

# Create Secret and then pipe to kubeseal to create the SealedSecret
secretYaml \
  | kubeseal -o yaml --controller-name sealed-secrets --controller-namespace infra > parts/ss-${SECRET_NAME}.yaml