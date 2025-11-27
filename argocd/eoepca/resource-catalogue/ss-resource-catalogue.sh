#!/usr/bin/env bash

ORIG_DIR="$(pwd)"
cd "$(dirname "$0")"
BIN_DIR="$(pwd)"

onExit() {
  cd "${ORIG_DIR}"
}
trap onExit EXIT

# Optional local .env file for secret values as env vars
source .env 2>/dev/null

SECRET_NAME="resource-catalogue-secret"
NAMESPACE="rm"

EOEPCA_DB_HOST="${1:-${EOEPCA_DB_HOST:-somehost}}"
EOEPCA_DB_NAME="${2:-${EOEPCA_DB_NAME:-somedbname}}"
EOEPCA_PORT="${3:-${EOEPCA_PORT:-someport}}"
EOEPCA_USER="${4:-${EOEPCA_USER:-someuser}}"
EOEPCA_PASSWORD="${5:-${EOEPCA_PASSWORD:-somesecret}}"

secretYaml() {
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="host=${EOEPCA_DB_HOST}" \
    --from-literal="dbname=${EOEPCA_DB_NAME}" \
    --from-literal="port=${EOEPCA_PORT}" \
    --from-literal="user=${EOEPCA_USER}" \
    --from-literal="password=${EOEPCA_PASSWORD}" \
    --dry-run=client -o yaml
}

# Create Secret and then pipe to kubeseal to create the SealedSecret
secretYaml \
  | kubeseal -o yaml --controller-name sealed-secrets --controller-namespace infra > parts/ss-${SECRET_NAME}.yaml
