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

SECRET_NAME="application-quality-auth-client"
NAMESPACE="application-quality"

APPLICATION_QUALITY_CLIENT_ID="${2:-${APPLICATION_QUALITY_CLIENT_ID:-application-quality-bb}}"
APPLICATION_QUALITY_CLIENT_SECRET="${2:-${APPLICATION_QUALITY_CLIENT_SECRET:-changeme}}"

secretYaml() {
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="OIDC_RP_CLIENT_ID=${APPLICATION_QUALITY_CLIENT_ID}" \
    --from-literal="OIDC_RP_CLIENT_SECRET=${APPLICATION_QUALITY_CLIENT_SECRET}" \
    --dry-run=client -o yaml
}

# Create Secret and then pipe to kubeseal to create the SealedSecret
secretYaml \
  | kubeseal -o yaml --controller-name sealed-secrets --controller-namespace infra > parts/ss-${SECRET_NAME}.yaml