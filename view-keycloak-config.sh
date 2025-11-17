#!/bin/bash

# Keycloak Configuration Viewer
# Shows all EURAC authentication configuration via REST API

set -e

KEYCLOAK_URL="http://localhost:8443"
REALM="eoepca"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║           Keycloak EURAC Configuration Viewer (REST API)                ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Get admin token
echo -e "${BLUE}► Getting admin access token...${NC}"
TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=changeme123" \
  -d "grant_type=password" | jq -r '.access_token')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo -e "${RED}✗ Failed to get admin token${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Admin token obtained${NC}"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "REALM INFORMATION"
echo "═══════════════════════════════════════════════════════════════════════════"

REALM_INFO=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}")

echo "Realm: $(echo "$REALM_INFO" | jq -r '.realm')"
echo "Display Name: $(echo "$REALM_INFO" | jq -r '.displayName')"
echo "Enabled: $(echo "$REALM_INFO" | jq -r '.enabled')"
echo "Login Theme: $(echo "$REALM_INFO" | jq -r '.loginTheme')"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "EURAC IDENTITY PROVIDER"
echo "═══════════════════════════════════════════════════════════════════════════"

EURAC_IDP=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research")

echo ""
echo -e "${BLUE}Basic Configuration:${NC}"
echo "  Alias:           $(echo "$EURAC_IDP" | jq -r '.alias')"
echo "  Display Name:    $(echo "$EURAC_IDP" | jq -r '.displayName')"
echo "  Enabled:         $(echo "$EURAC_IDP" | jq -r '.enabled')"
echo "  Provider Type:   $(echo "$EURAC_IDP" | jq -r '.providerId')"
echo "  Trust Email:     $(echo "$EURAC_IDP" | jq -r '.trustEmail')"
echo "  Store Token:     $(echo "$EURAC_IDP" | jq -r '.storeToken')"
echo ""

echo -e "${BLUE}SAML Configuration:${NC}"
echo "  SSO Service URL: $(echo "$EURAC_IDP" | jq -r '.config.singleSignOnServiceUrl')"
echo "  Entity ID:       $(echo "$EURAC_IDP" | jq -r '.config.entityId')"
echo "  Name ID Format:  $(echo "$EURAC_IDP" | jq -r '.config.nameIDPolicyFormat')"
echo "  Sign Requests:   $(echo "$EURAC_IDP" | jq -r '.config.wantAuthnRequestsSigned')"
echo "  Validate Sig:    $(echo "$EURAC_IDP" | jq -r '.config.validateSignature')"
echo "  Post Binding:    $(echo "$EURAC_IDP" | jq -r '.config.postBindingResponse')"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "ATTRIBUTE MAPPERS"
echo "═══════════════════════════════════════════════════════════════════════════"

MAPPERS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research/mappers")

echo ""
echo "$MAPPERS" | jq -r '.[] | "  • \(.name)\n    SAML Attribute: \(.config."attribute.name")\n    User Attribute: \(.config."user.attribute" // "N/A")\n    Type: \(.identityProviderMapper)\n"'

MAPPER_COUNT=$(echo "$MAPPERS" | jq '. | length')
echo "Total Mappers: $MAPPER_COUNT"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "OPENEO OIDC CLIENT"
echo "═══════════════════════════════════════════════════════════════════════════"

OPENEO_CLIENT=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq '.[] | select(.clientId == "openeo")')

echo ""
echo -e "${BLUE}Client Configuration:${NC}"
echo "  Client ID:       $(echo "$OPENEO_CLIENT" | jq -r '.clientId')"
echo "  Name:            $(echo "$OPENEO_CLIENT" | jq -r '.name // "N/A"')"
echo "  Enabled:         $(echo "$OPENEO_CLIENT" | jq -r '.enabled')"
echo "  Protocol:        $(echo "$OPENEO_CLIENT" | jq -r '.protocol')"
echo "  Public Client:   $(echo "$OPENEO_CLIENT" | jq -r '.publicClient')"
echo "  Standard Flow:   $(echo "$OPENEO_CLIENT" | jq -r '.standardFlowEnabled')"
echo "  Direct Access:   $(echo "$OPENEO_CLIENT" | jq -r '.directAccessGrantsEnabled')"
echo ""

echo -e "${BLUE}Redirect URIs:${NC}"
echo "$OPENEO_CLIENT" | jq -r '.redirectUris[]' | sed 's/^/  • /'
echo ""

echo -e "${BLUE}Web Origins:${NC}"
WEB_ORIGINS=$(echo "$OPENEO_CLIENT" | jq -r '.webOrigins[]' 2>/dev/null || echo "  None configured")
if [ "$WEB_ORIGINS" != "  None configured" ]; then
    echo "$WEB_ORIGINS" | sed 's/^/  • /'
else
    echo "$WEB_ORIGINS"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "GROUPS"
echo "═══════════════════════════════════════════════════════════════════════════"

GROUPS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/groups")

echo ""
if [ "$(echo "$GROUPS" | jq '. | length')" -gt 0 ]; then
    echo "$GROUPS" | jq -r '.[] | "  • \(.name)\n    ID: \(.id)\n    Path: \(.path)\n"'
else
    echo "  No groups configured"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "USERS"
echo "═══════════════════════════════════════════════════════════════════════════"

USERS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/users")

USER_COUNT=$(echo "$USERS" | jq '. | length')
echo ""
echo "Total Users: $USER_COUNT"
echo ""

if [ "$USER_COUNT" -gt 0 ]; then
    echo "$USERS" | jq -r '.[] | "  • \(.username) (\(.email // "no email"))\n    Enabled: \(.enabled)\n    Created: \(.createdTimestamp)\n"'
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "OIDC DISCOVERY"
echo "═══════════════════════════════════════════════════════════════════════════"

DISCOVERY=$(curl -s "${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration")

echo ""
echo -e "${BLUE}Key Endpoints:${NC}"
echo "  Issuer:          $(echo "$DISCOVERY" | jq -r '.issuer')"
echo "  Authorization:   $(echo "$DISCOVERY" | jq -r '.authorization_endpoint')"
echo "  Token:           $(echo "$DISCOVERY" | jq -r '.token_endpoint')"
echo "  UserInfo:        $(echo "$DISCOVERY" | jq -r '.userinfo_endpoint')"
echo "  JWKs:            $(echo "$DISCOVERY" | jq -r '.jwks_uri')"
echo ""

echo -e "${BLUE}Supported Features:${NC}"
echo "  Grant Types:     $(echo "$DISCOVERY" | jq -r '.grant_types_supported | join(", ")')"
echo "  Response Types:  $(echo "$DISCOVERY" | jq -r '.response_types_supported | join(", ")')"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "QUICK LINKS FOR BROWSER TESTING"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "EURAC Login URL (test in browser):"
echo "  ${KEYCLOAK_URL}/realms/${REALM}/broker/eurac-research/login"
echo ""
echo "OIDC Discovery:"
echo "  ${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration"
echo ""
echo "Account Console (for end users):"
echo "  ${KEYCLOAK_URL}/realms/${REALM}/account/"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ Configuration retrieval complete!${NC}"
echo "═══════════════════════════════════════════════════════════════════════════"
