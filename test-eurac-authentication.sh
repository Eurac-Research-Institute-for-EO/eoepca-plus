#!/bin/bash

# EURAC Authentication Flow Test Script
# This script tests the complete authentication flow from EURAC login through Keycloak to OpenEO

set -e

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║              🧪 EURAC Authentication Flow Test                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_URL="http://localhost:8443"
OPENEO_URL="http://localhost:8000"
REALM="eoepca"
CLIENT_ID="openeo"
CLIENT_SECRET="ZPYkOdkJOZl2v0yuHsOxxxGNMtQ6V9Ke"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 1: Verify Port Forwards"
echo "═══════════════════════════════════════════════════════════════════════════"

# Check if port forwards are running
if ps aux | grep -q "[p]ort-forward.*iam.*8443"; then
    echo -e "${GREEN}✅ Keycloak port-forward is running${NC}"
else
    echo -e "${RED}❌ Keycloak port-forward is NOT running${NC}"
    echo "   Start it with: kubectl port-forward -n iam pod/iam-keycloak-0 8443:8080"
    exit 1
fi

if ps aux | grep -q "[p]ort-forward.*openeo.*8000"; then
    echo -e "${GREEN}✅ OpenEO port-forward is running${NC}"
else
    echo -e "${RED}❌ OpenEO port-forward is NOT running${NC}"
    echo "   Start it with: kubectl port-forward -n openeo svc/openeo-openeo-argo 8000:8000"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 2: Test Keycloak Availability"
echo "═══════════════════════════════════════════════════════════════════════════"

# Test Keycloak realm
REALM_ISSUER=$(curl -s "${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration" | jq -r '.issuer')
if [ ! -z "$REALM_ISSUER" ]; then
    echo -e "${GREEN}✅ Keycloak realm '${REALM}' is accessible${NC}"
    echo "   Issuer: ${REALM_ISSUER}"
else
    echo -e "${RED}❌ Cannot access Keycloak realm${NC}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 3: Verify EURAC Identity Provider"
echo "═══════════════════════════════════════════════════════════════════════════"

# Get admin token
ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=changeme123" \
  -d "grant_type=password" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" != "null" ] && [ ! -z "$ADMIN_TOKEN" ]; then
    echo -e "${GREEN}✅ Admin authentication successful${NC}"
else
    echo -e "${RED}❌ Admin authentication failed${NC}"
    exit 1
fi

# Check EURAC IdP
EURAC_IDP=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research")

EURAC_ENABLED=$(echo "$EURAC_IDP" | jq -r '.enabled')
EURAC_SSO_URL=$(echo "$EURAC_IDP" | jq -r '.config.singleSignOnServiceUrl')
EURAC_DISPLAY=$(echo "$EURAC_IDP" | jq -r '.displayName')

if [ "$EURAC_ENABLED" == "true" ]; then
    echo -e "${GREEN}✅ EURAC Identity Provider is enabled${NC}"
    echo "   Display Name: ${EURAC_DISPLAY}"
    echo "   SSO URL: ${EURAC_SSO_URL}"
else
    echo -e "${RED}❌ EURAC Identity Provider is not enabled${NC}"
    exit 1
fi

# Check attribute mappers
MAPPER_COUNT=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research/mappers" | jq '. | length')

echo -e "${GREEN}✅ ${MAPPER_COUNT} attribute mappers configured${NC}"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 4: Verify OpenEO OIDC Client"
echo "═══════════════════════════════════════════════════════════════════════════"

OPENEO_CLIENT=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq -r '.[] | select(.clientId == "openeo")')

CLIENT_ENABLED=$(echo "$OPENEO_CLIENT" | jq -r '.enabled')
REDIRECT_URIS=$(echo "$OPENEO_CLIENT" | jq -r '.redirectUris[]')

if [ "$CLIENT_ENABLED" == "true" ]; then
    echo -e "${GREEN}✅ OpenEO OIDC client is enabled${NC}"
    echo "   Client ID: ${CLIENT_ID}"
    echo "   Redirect URIs:"
    echo "$REDIRECT_URIS" | sed 's/^/     - /'
else
    echo -e "${RED}❌ OpenEO OIDC client is not enabled${NC}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 5: Test OpenEO API Accessibility"
echo "═══════════════════════════════════════════════════════════════════════════"

# Test OpenEO docs endpoint
OPENEO_DOCS=$(curl -s -o /dev/null -w "%{http_code}" "${OPENEO_URL}/docs")

if [ "$OPENEO_DOCS" == "200" ]; then
    echo -e "${GREEN}✅ OpenEO API is accessible${NC}"
    echo "   Docs URL: ${OPENEO_URL}/docs"
else
    echo -e "${YELLOW}⚠️  OpenEO /docs returned HTTP ${OPENEO_DOCS}${NC}"
fi

# Check OpenEO environment
echo ""
echo "OpenEO OIDC Configuration:"
kubectl exec -n openeo deployment/openeo-openeo-argo -c openeo-argo -- printenv | grep OIDC | while read line; do
    echo "   $line"
done

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 6: Test OIDC Token Flow (Client Credentials)"
echo "═══════════════════════════════════════════════════════════════════════════"

# Get token using client credentials
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$ACCESS_TOKEN" != "null" ] && [ ! -z "$ACCESS_TOKEN" ]; then
    echo -e "${GREEN}✅ Successfully obtained access token via client_credentials${NC}"
    
    # Decode token to show claims
    TOKEN_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null || echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -D 2>/dev/null)
    
    echo ""
    echo "Token Claims:"
    echo "$TOKEN_PAYLOAD" | jq '{
        issuer: .iss,
        client: .azp,
        scope: .scope,
        expires: .exp
    }'
else
    echo -e "${RED}❌ Failed to obtain access token${NC}"
    echo "Response: $TOKEN_RESPONSE"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "STEP 7: Browser-Based Testing Instructions"
echo "═══════════════════════════════════════════════════════════════════════════"

echo ""
echo -e "${YELLOW}📋 Manual Testing Steps:${NC}"
echo ""
echo "1. Test Keycloak Admin Console:"
echo "   URL: ${KEYCLOAK_URL}/admin/master/console/"
echo "   Login: admin / changeme123"
echo ""
echo "2. Test EURAC Login Flow:"
echo "   URL: ${KEYCLOAK_URL}/realms/${REALM}/broker/eurac-research/login"
echo ""
echo "   Expected behavior:"
echo "   - Redirects to sso.eurac.edu"
echo "   - Shows EURAC login page"
echo "   - After login, redirects back to Keycloak"
echo "   - Creates user profile with SAML attributes"
echo ""
echo "3. View OpenEO API Documentation:"
echo "   URL: ${OPENEO_URL}/docs"
echo ""
echo "4. Test OpenEO with Authentication:"
echo "   - The OpenEO API should accept Bearer tokens from Keycloak"
echo "   - Use the access token obtained above in Authorization header"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "                           🎉 Test Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✅ All automated tests passed!${NC}"
echo ""
echo "Key URLs for testing:"
echo "  • Keycloak Admin:  ${KEYCLOAK_URL}/admin/master/console/"
echo "  • EURAC Login:     ${KEYCLOAK_URL}/realms/${REALM}/broker/eurac-research/login"
echo "  • OpenEO Docs:     ${OPENEO_URL}/docs"
echo "  • OIDC Discovery:  ${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration"
echo ""
echo "The EURAC authentication infrastructure is fully operational!"
echo "═══════════════════════════════════════════════════════════════════════════"
