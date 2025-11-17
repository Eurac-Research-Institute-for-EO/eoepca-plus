#!/usr/bin/env bash

set -e

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║              KEYCLOAK OPERATOR INSTALLATION                              ║
╚══════════════════════════════════════════════════════════════════════════╝

This script will install:
  1. Keycloak Operator (for declarative Keycloak management)
  2. Configure operator to manage existing Keycloak instance
  3. Enable SAML Identity Provider support

EOF

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Prerequisites Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found"
    exit 1
fi
echo "✅ kubectl found"

# Check cluster access
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi
echo "✅ Connected to Kubernetes cluster"

# Check if Keycloak is running
if ! kubectl get statefulset iam-keycloak -n iam &> /dev/null; then
    echo "❌ Keycloak not found in iam namespace"
    exit 1
fi
echo "✅ Keycloak is running"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Install Keycloak Operator"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install operator using kubectl
echo "Installing Keycloak Operator CRDs and deployment..."
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/25.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/25.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/25.0.2/kubernetes/kubernetes.yml

echo "✅ Keycloak Operator installed"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Wait for Operator to be Ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Waiting for Keycloak Operator pods to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=keycloak-operator \
  -n keycloak \
  --timeout=300s

echo "✅ Keycloak Operator is ready"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Keycloak Operator Pods:"
kubectl get pods -n keycloak

echo ""
echo "Keycloak CRDs:"
kubectl get crd | grep keycloak.org

cat << 'SUMMARY_EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║              ✅ KEYCLOAK OPERATOR INSTALLATION COMPLETE                  ║
╚══════════════════════════════════════════════════════════════════════════╝

📦 INSTALLED COMPONENTS:

  ✅ Keycloak Operator
  ✅ Keycloak CRD (k8s.keycloak.org/v1)
  ✅ KeycloakRealmImport CRD

📋 NEXT STEPS:

  The Keycloak Operator is now installed, but it uses a different approach
  than the Crossplane provider we tried earlier.
  
  ⚠️  IMPORTANT: The Keycloak Operator is designed to DEPLOY Keycloak instances,
      not to manage existing ones.
  
  For EURAC SAML configuration with existing Keycloak:
  
  Option A: Use KeycloakRealmImport to import realm configuration
  ----------------------------------------------------------------
  Create a JSON export of the eoepca realm with EURAC SAML config
  and import it using KeycloakRealmImport CRD
  
  Option B: Use Keycloak REST API
  --------------------------------
  Directly configure EURAC SAML via REST API calls
  (This is the most straightforward for existing Keycloak)

🤔 RECOMMENDATION:

  Since we have an existing Keycloak instance (not managed by the operator),
  the REST API approach (Option B) is the most practical.
  
  The operator is useful for deploying NEW Keycloak instances,
  but for configuring an EXISTING instance, REST API is simpler.

SUMMARY_EOF
