#!/bin/bash

echo "=== Monitoring OpenEO Authentication Logs ==="
echo "Press Ctrl+C to stop monitoring"
echo ""
echo "Watching APISIX gateway logs for OpenEO traffic..."
echo "==========================================="

kubectl logs -n iam iam-keycloak-apisix-7b8b87bdbf-b978n -f --tail=0 2>&1 | grep --line-buffered -iE "openeo-eurac|redirect|error|500|localhost" | while read line; do
    echo "[$(date '+%H:%M:%S')] $line"
done
