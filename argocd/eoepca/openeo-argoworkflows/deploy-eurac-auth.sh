#!/usr/bin/env bash

# Script to create deployment script for EURAC authentication
# This script documents the deployment steps

ORIG_DIR="$(pwd)"
cd "$(dirname "$0")"
BIN_DIR="$(pwd)"

onExit() {
  cd "${ORIG_DIR}"
}
trap onExit EXIT

echo "=========================================="
echo "EURAC Authentication Deployment Script"
echo "=========================================="
echo ""

# Check if running in correct directory
if [[ ! -f "parts/keycloak-idp-eurac.yaml" ]]; then
  echo "❌ Error: Please run this script from argocd/eoepca/openeo-argoworkflows/"
  exit 1
fi

echo "Step 1: Verify Keycloak is running..."
if kubectl get pods -n iam -l app.kubernetes.io/name=keycloak | grep -q Running; then
  echo "✅ Keycloak is running"
else
  echo "❌ Keycloak is not running. Please deploy IAM Building Block first."
  exit 1
fi

echo ""
echo "Step 2: Verify eoepca realm exists..."
if kubectl get realm -n iam eoepca &>/dev/null; then
  echo "✅ Realm 'eoepca' exists"
else
  echo "❌ Realm 'eoepca' does not exist. Please configure IAM first."
  exit 1
fi

echo ""
echo "Step 3: Apply EURAC Identity Provider..."
kubectl apply -f parts/keycloak-idp-eurac.yaml
echo "⏳ Waiting for Identity Provider to be ready..."
kubectl wait --for=condition=Ready identityprovider/eurac-research-saml -n iam --timeout=300s
echo "✅ EURAC Identity Provider created"

echo ""
echo "Step 4: Apply EURAC attribute mappers..."
kubectl apply -f parts/keycloak-eurac-mappers.yaml
echo "✅ Attribute mappers configured"

echo ""
echo "Step 5: Create EURAC researchers group..."
kubectl apply -f parts/keycloak-eurac-group.yaml
echo "✅ EURAC researchers group created"

echo ""
echo "Step 6: Get Service Provider metadata for EURAC registration..."
echo "📋 SP Metadata URL:"
echo "   https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor"
echo ""
echo "📧 Send this information to EURAC IT (it-support@eurac.edu):"
echo "   - Entity ID: https://iam-auth.develop.eoepca.org/realms/eoepca"
echo "   - ACS URL: https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint"
echo "   - Metadata: https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor"

echo ""
echo "=========================================="
echo "✅ EURAC Authentication Deployment Complete!"
echo "=========================================="
echo ""
echo "🧪 Test EURAC Login:"
echo "   1. Go to OpenEO Web Editor"
echo "   2. Click 'Login with EURAC Research'"
echo "   3. Enter your EURAC credentials"
echo "   4. Verify you can access OpenEO API"
echo ""
echo "📊 Monitor authentication:"
echo "   kubectl logs -n iam deployment/iam-keycloak -f | grep eurac"
echo ""
echo "🔍 Verify users:"
echo "   kubectl get users -n iam"
echo ""
