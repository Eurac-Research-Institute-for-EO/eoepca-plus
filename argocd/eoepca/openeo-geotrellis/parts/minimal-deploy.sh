#!/bin/bash
set -e

echo "🚀 Deploying OpenEO GeoPySpark - Minimal Setup for Testing"
echo ""
echo "⚠️  Note: This is a simplified deployment for testing EURAC authentication"
echo "   Full production deployment requires proper storage and resources"
echo ""

# Add Helm repo
echo "📦 Adding VITO Helm repository..."
helm repo add vito https://artifactory.vgt.vito.be/artifactory/helm-charts 2>/dev/null || true
helm repo update

# Create namespace
kubectl create namespace openeo-geotrellis --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Step 1/2: Deploying Zookeeper with standard storage..."
helm upgrade --install openeo-geotrellis-zookeeper \
  vito/zookeeper \
  --version 11.1.6 \
  --namespace openeo-geotrellis \
  --values values-openeo-geotrellis-zookeeper.yaml \
  --wait \
  --timeout 10m

echo ""
echo "Step 2/2: Deploying OpenEO application (this may take a while)..."
helm upgrade --install openeo-geotrellis-openeo \
  vito/sparkapplication \
  --version 1.0.2 \
  --namespace openeo-geotrellis \
  --values values-openeo-geotrellis-openeo.yaml \
  --timeout 15m

echo ""
echo "✅ Deployment initiated!"
echo ""
echo "📋 Monitor deployment:"
echo "   watch kubectl get pods -n openeo-geotrellis"
echo ""
echo "🔍 Once running, test OIDC endpoint:"
echo "   kubectl port-forward --address 0.0.0.0 -n openeo-geotrellis svc/openeo-geotrellis-openeo 8081:80 &"
echo "   curl http://10.8.244.73:8081/credentials/oidc | jq '.providers[] | {id, title, issuer}'"
echo ""
