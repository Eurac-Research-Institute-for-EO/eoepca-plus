#!/usr/bin/env bash

set -e

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║              CROSSPLANE INSTALLATION FOR KEYCLOAK MANAGEMENT             ║
╚══════════════════════════════════════════════════════════════════════════╝

This script will install:
  1. Crossplane (Universal Control Plane)
  2. Crossplane Keycloak Provider
  3. ProviderConfig for connecting to Keycloak

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

# Check helm
if ! command -v helm &> /dev/null; then
    echo "❌ helm not found"
    exit 1
fi
echo "✅ helm found"

# Check cluster access
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi
echo "✅ Connected to Kubernetes cluster"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Install Crossplane"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Add Crossplane Helm repository
echo "Adding Crossplane Helm repository..."
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Create namespace
echo "Creating crossplane-system namespace..."
kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

# Install Crossplane
echo "Installing Crossplane..."
helm upgrade --install crossplane \
  --namespace crossplane-system \
  crossplane-stable/crossplane \
  --version 1.14.5 \
  --wait

echo "✅ Crossplane installed"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Wait for Crossplane to be Ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Waiting for Crossplane pods to be ready..."
kubectl wait --for=condition=ready pod \
  -l app=crossplane \
  -n crossplane-system \
  --timeout=300s

echo "✅ Crossplane is ready"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Install Crossplane Keycloak Provider"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install Keycloak Provider
cat <<PROVIDER_EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-keycloak
spec:
  package: crossplane/provider-keycloak:v0.3.0
PROVIDER_EOF

echo "✅ Keycloak Provider installed"

echo ""
echo "Waiting for Keycloak Provider to be healthy..."
kubectl wait --for=condition=healthy provider/provider-keycloak --timeout=300s

echo "✅ Keycloak Provider is healthy"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Configure Keycloak Provider"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create secret for Keycloak credentials
kubectl create secret generic keycloak-credentials \
  -n crossplane-system \
  --from-literal=username=admin \
  --from-literal=password=changeme123 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Keycloak credentials secret created"

# Create ProviderConfig
cat <<PROVIDERCONFIG_EOF | kubectl apply -f -
apiVersion: keycloak.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: keycloak-provider
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: keycloak-credentials
      key: password
  username: admin
  url: http://iam-keycloak.iam.svc.cluster.local
PROVIDERCONFIG_EOF

echo "✅ ProviderConfig created"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Crossplane Pods:"
kubectl get pods -n crossplane-system

echo ""
echo "Installed Providers:"
kubectl get providers

echo ""
echo "Provider Configs:"
kubectl get providerconfigs

cat << 'SUMMARY_EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║                    ✅ CROSSPLANE INSTALLATION COMPLETE                   ║
╚══════════════════════════════════════════════════════════════════════════╝

📦 INSTALLED COMPONENTS:

  ✅ Crossplane v1.14.5
  ✅ Crossplane Keycloak Provider v0.3.0
  ✅ ProviderConfig pointing to Keycloak

📋 NEXT STEPS:

  Now you can apply the EURAC SAML configuration:
  
  cd /home/yadagale/eoepca-plus/eoepca-plus/argocd/eoepca/openeo-argoworkflows
  ./deploy-eurac-auth.sh

⚠️  IMPORTANT NOTES:

  • The ProviderConfig uses cluster-internal Keycloak URL
  • Credentials are stored in crossplane-system/keycloak-credentials
  • The provider may take a few minutes to fully initialize
  • Check provider logs if you encounter issues:
    kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-keycloak

SUMMARY_EOF
