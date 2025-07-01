#!/usr/bin/bash

set -e

ORIG_DIR="$(pwd)"
cd "$(dirname "$0")"

onExit() {
  cd "${ORIG_DIR}"
}
trap onExit EXIT

# Optional local .env file for secret values as env vars
source .env 2>/dev/null

SECRET_NAME="openeo-geotrellis-data-bucket-credentials"
NAMESPACE="openeo-geotrellis"

AWS_SECRET_ACCESS_KEY="${2:-${AWS_SECRET_ACCESS_KEY:-changeme}}"

secretYaml() {
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml
}

# Create Secret and then pipe to kubeseal to create the SealedSecret
secretYaml \
  | kubeseal -o yaml --controller-name sealed-secrets --controller-namespace infra > parts/ss-${SECRET_NAME}.yaml
