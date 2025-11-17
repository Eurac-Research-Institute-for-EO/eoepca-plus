#!/bin/bash
set -e

echo "🚀 Deploying OpenEO GeoPySpark with EURAC Authentication"
echo ""

# Add Helm repo
echo "📦 Adding VITO Helm repository..."
helm repo add vito https://artifactory.vgt.vito.be/artifactory/helm-charts 2>/dev/null || true
helm repo update

# Create namespace
echo "📂 Creating openeo-geotrellis namespace..."
kubectl create namespace openeo-geotrellis --dry-run=client -o yaml | kubectl apply -f -

# Deploy Zookeeper first
echo "🐘 Deploying Zookeeper..."
kubectl apply -f openeo-geotrellis-zookeeper.yaml

# Wait for Zookeeper
echo "⏳ Waiting for Zookeeper to be ready..."
sleep 10

# Deploy Spark Operator
echo "⚡ Deploying Spark Operator..."
kubectl apply -f openeo-geotrellis-sparkoperator.yaml

# Wait for Spark Operator
echo "⏳ Waiting for Spark Operator to be ready..."
sleep 10

# Deploy RBAC
echo "🔐 Deploying RBAC..."
kubectl apply -f openeo-geotrellis-batch-rbac.yaml

# Deploy OpenEO application with EURAC authentication
echo "🌍 Deploying OpenEO GeoPySpark with EURAC provider..."
helm upgrade --install openeo-geotrellis-openeo \
  vito/sparkapplication \
  --version 1.0.2 \
  --namespace openeo-geotrellis \
  --values values-openeo-geotrellis-openeo.yaml \
  --wait

echo ""
echo "✅ Deployment complete!"
echo ""
echo "�� Check status:"
echo "   kubectl get pods -n openeo-geotrellis"
echo ""
echo "🔍 Test OIDC endpoint (after port-forward):"
echo "   kubectl port-forward -n openeo-geotrellis svc/openeo-geotrellis-openeo 8080:80"
echo "   curl http://localhost:8080/credentials/oidc | jq '.providers'"
echo ""
