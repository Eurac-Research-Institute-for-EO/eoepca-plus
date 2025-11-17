#!/usr/bin/env bash

# IAM Building Block (Keycloak) - Direct Deployment Script
# This deploys Keycloak without ArgoCD for testing purposes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║     IAM Building Block (Keycloak) - Direct Deployment           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check prerequisites
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Prerequisites Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ kubectl found${NC}"

# Check helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ helm not found. Please install helm: https://helm.sh/docs/intro/install/${NC}"
    exit 1
fi
echo -e "${GREEN}✅ helm found${NC}"

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Create IAM Namespace"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get namespace iam &> /dev/null; then
    echo -e "${YELLOW}⚠️  Namespace 'iam' already exists${NC}"
else
    kubectl create namespace iam
    echo -e "${GREEN}✅ Namespace 'iam' created${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Add Helm Repositories"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Add EOEPCA Helm repo
echo "Adding EOEPCA Helm repository..."
helm repo add eoepca-dev https://eoepca.github.io/helm-charts-dev 2>/dev/null || true
helm repo update
echo -e "${GREEN}✅ EOEPCA Helm repository added${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Prepare Keycloak Values"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VALUES_FILE="parts/values/iam-values.yaml"

if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Values file not found: $VALUES_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Using values file: $VALUES_FILE${NC}"

# Check if we're in the correct directory
if [[ ! -d "parts" ]]; then
    echo -e "${YELLOW}⚠️  Not in iam directory. Changing directory...${NC}"
    cd ../iam
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Deploy IAM Building Block (Keycloak)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat << 'INFO'

⚠️  IMPORTANT NOTICE:

This will deploy Keycloak with the following configuration:
  - Chart: eoepca-dev/iam-bb (version 2.0.0-rc2.4)
  - Namespace: iam
  - Keycloak: Enabled
  - OPA: Disabled (can be enabled later)
  - OPAL: Disabled (can be enabled later)
  - Identity API: Disabled (can be enabled later)

The deployment may take 5-10 minutes.

INFO

read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

echo ""
echo "Installing IAM Building Block..."

# Create minimal values override for Keycloak only
cat > /tmp/keycloak-deploy-values.yaml << 'YAML'
# Minimal IAM BB deployment - Keycloak only
global:
  storageClass: "standard"  # Adjust if needed

iam:
  keycloak:
    enabled: true
    createRoute: false  # No ingress for now
    url: http://iam-keycloak.iam.svc.cluster.local
    configuration:
      useCrossplane: false  # Disable Crossplane for simple deployment
      useKeycloakConfigCli: false
      createClients: false
      realm:
        create: false
        name: eoepca

  opa:
    enabled: false
  
  identityApi:
    enabled: false

keycloak:
  enabled: true
  auth:
    adminUser: admin
    adminPassword: "changeme123"  # Change this!
  postgresql:
    enabled: true
    auth:
      username: keycloak
      password: "changeme123"  # Change this!
      database: keycloak
  service:
    type: ClusterIP
    ports:
      http: 80

# Disable other components
iam-bb-config:
  enabled: false

opal:
  enabled: false
YAML

echo "Deploying Keycloak..."
helm upgrade --install iam-keycloak \
  eoepca-dev/iam-bb \
  --version 2.0.0-rc2.4 \
  --namespace iam \
  --values /tmp/keycloak-deploy-values.yaml \
  --timeout 10m \
  --wait

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ IAM Building Block deployed successfully!${NC}"
else
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Verify Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n iam --timeout=300s || true

echo ""
echo "Keycloak Pods:"
kubectl get pods -n iam -l app.kubernetes.io/name=keycloak

echo ""
echo "Keycloak Service:"
kubectl get svc -n iam -l app.kubernetes.io/name=keycloak

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7: Access Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

KC_SERVICE=$(kubectl get svc -n iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "iam-keycloak")

cat << INFO

╔════════════════════════════════════════════════════════════════╗
║                  Keycloak Deployed Successfully!               ║
╚════════════════════════════════════════════════════════════════╝

📋 Access Information:

  Keycloak Service: ${KC_SERVICE}.iam.svc.cluster.local
  Admin Username:   admin
  Admin Password:   changeme123

🔧 Access Keycloak Admin Console:

  # Port forward to access Keycloak
  kubectl port-forward -n iam svc/${KC_SERVICE} 8080:80

  # Then open in browser:
  http://localhost:8080

🚀 Next Steps:

  1. Create EOEPCA realm in Keycloak
  2. Configure EURAC Identity Provider
  3. Apply EURAC authentication configs:
     cd ../openeo-argoworkflows
     ./deploy-eurac-auth.sh

⚠️  Security Notice:
  - Change the default admin password!
  - Use Sealed Secrets for production
  - Configure proper ingress/TLS

INFO

echo ""
echo -e "${GREEN}✅ Deployment complete!${NC}"
