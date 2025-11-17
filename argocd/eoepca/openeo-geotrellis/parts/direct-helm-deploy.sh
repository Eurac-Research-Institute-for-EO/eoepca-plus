#!/bin/bash
set -e

echo "🚀 Deploying OpenEO GeoPySpark with EURAC Authentication (Direct Helm)"
echo ""

# Add Helm repo
echo "�� Adding VITO Helm repository..."
helm repo add vito https://artifactory.vgt.vito.be/artifactory/helm-charts 2>/dev/null || true
helm repo update

# Create namespace
echo "📂 Creating openeo-geotrellis namespace..."
kubectl create namespace openeo-geotrellis --dry-run=client -o yaml | kubectl apply -f -

# Deploy components using Helm directly
echo ""
echo "Step 1/3: Deploying Zookeeper..."
helm upgrade --install openeo-geotrellis-zookeeper \
  vito/zookeeper \
  --version 11.1.6 \
  --namespace openeo-geotrellis \
  --values values-openeo-geotrellis-zookeeper.yaml \
  --wait \
  --timeout 5m

echo ""
echo "Step 2/3: Deploying Spark Operator..."
helm upgrade --install openeo-geotrellis-sparkoperator \
  vito/spark-operator \
  --version 1.1.27 \
  --namespace openeo-geotrellis \
  --values values-openeo-geotrellis-sparkoperator.yaml \
  --wait \
  --timeout 5m

echo ""
echo "Step 3/3: Deploying OpenEO with EURAC authentication..."
helm upgrade --install openeo-geotrellis-openeo \
  vito/sparkapplication \
  --version 1.0.2 \
  --namespace openeo-geotrellis \
  --values values-openeo-geotrellis-openeo.yaml \
  --wait \
  --timeout 10m

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Check deployment status:"
echo "   kubectl get pods -n openeo-geotrellis"
echo ""
echo "🔍 Get service details:"
echo "   kubectl get svc -n openeo-geotrellis"
echo ""
echo "🌐 Test OIDC endpoint (after port-forward):"
echo "   kubectl port-forward -n openeo-geotrellis svc/openeo-geotrellis-openeo 8080:80"
echo "   curl http://localhost:8080/credentials/oidc | jq '.providers[]'"
echo ""
