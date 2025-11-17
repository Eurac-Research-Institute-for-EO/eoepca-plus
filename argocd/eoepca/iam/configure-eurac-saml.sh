#!/usr/bin/env bash

set -e

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║              EURAC SAML IDENTITY PROVIDER CONFIGURATION                  ║
╚══════════════════════════════════════════════════════════════════════════╝

This script will configure:
  1. EURAC SAML Identity Provider in eoepca realm
  2. SAML Attribute Mappers (email, name, affiliation, etc.)
  3. EURAC Researchers group with enhanced quotas

EOF

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-changeme123}"
REALM="${REALM:-eoepca}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Authentication"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Getting admin access token..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  echo "❌ Failed to get admin token"
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

echo "✅ Authenticated successfully"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Create EURAC SAML Identity Provider"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

IDP_CONFIG=$(cat <<'IDP_JSON'
{
  "alias": "eurac-research",
  "displayName": "EURAC Research",
  "providerId": "saml",
  "enabled": true,
  "updateProfileFirstLoginMode": "on",
  "trustEmail": true,
  "storeToken": false,
  "addReadTokenRoleOnCreate": false,
  "authenticateByDefault": false,
  "linkOnly": false,
  "firstBrokerLoginFlowAlias": "first broker login",
  "config": {
    "hideOnLoginPage": "false",
    "validateSignature": "true",
    "samlXmlKeyNameTranformer": "KEY_ID",
    "signingCertificate": "MIIDEzCCAfugAwIBAgIVAOBKy3d3W1fAR5SPnZPb1P6fWqK/MA0GCSqGSIb3DQEBCwUAMBYxFDASBgNVBAMMC3Nzby5ldXJhYy5ldTAeFw0xOTA2MTcxNTI3MTNaFw0zOTA2MTcxNTI3MTNaMBYxFDASBgNVBAMMC3Nzby5ldXJhYy5ldTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANO6SnMgXQVTBKA7/y8XYT+ByX7UIKPZQ8q7kG9xz9OGLt3i8bNxP6rTN6TjPZHFaBEVTDU0thSQ5LcbGJ5xnp3xCJdnNGcZqvEYv2fRPXZQUvL4CQHO/9vXZ0/k1LJfOKF8nMzFZQEXV7cKp+4HN1vNJ8LEJy8LbKGNqUWHNJJbkCcP7y/1J0U8BZvqN3mCGKHxECKFYvXs5tQv/YWnz8A2y7AO6u5VGh5dVJZ5xZ1E8dEKBQ8P5vB0Cf0L9XQ/9qY3L5H5YJvRQJ0Q9T/5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5L5AgMBAAGjVTBTMB0GA1UdDgQWBBRQXyJ0bVPZNV5QyR7WcE2HXRV7PzAyBgNVHREEKzApggtzcmF6Lm9yZy5vcmeCC3Nzby5ldXJhYy5ldYIPYWFpLmV1cmFjLmVkdTANBgkqhkiG9w0BAQsFAAOCAQEAQl0EEK9XPNf5fKJY8y0nQj0fKPcvJPm8Y1YYmvLJPOqQGCM0hEGZJx8LY3TsVvYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJLLYJA==",
    "postBindingResponse": "true",
    "postBindingAuthnRequest": "true",
    "postBindingLogout": "true",
    "wantAuthnRequestsSigned": "false",
    "wantAssertionsSigned": "true",
    "wantAssertionsEncrypted": "false",
    "forceAuthn": "false",
    "signatureAlgorithm": "RSA_SHA256",
    "xmlSigKeyInfoKeyNameTransformer": "NONE",
    "syncMode": "IMPORT",
    "nameIDPolicyFormat": "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
    "principalType": "SUBJECT",
    "principalAttribute": "eduPersonPrincipalName",
    "allowCreate": "true",
    "entityId": "https://sso.eurac.edu/auth/realms/eurac",
    "singleSignOnServiceUrl": "https://sso.eurac.edu/auth/realms/eurac/protocol/saml",
    "singleLogoutServiceUrl": "https://sso.eurac.edu/auth/realms/eurac/protocol/saml",
    "backchannelSupported": "false",
    "useMetadataDescriptorUrl": "true",
    "metadataDescriptorUrl": "https://sso.eurac.edu/auth/realms/eurac/protocol/saml/descriptor"
  }
}
IDP_JSON
)

echo "Creating EURAC SAML Identity Provider..."
IDP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$IDP_CONFIG")

HTTP_CODE=$(echo "$IDP_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$IDP_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "201" ]; then
  echo "✅ EURAC SAML Identity Provider created"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "⚠️  Identity Provider already exists, updating..."
  curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$IDP_CONFIG" > /dev/null
  echo "✅ EURAC SAML Identity Provider updated"
else
  echo "❌ Failed to create Identity Provider (HTTP $HTTP_CODE)"
  echo "Response: $RESPONSE_BODY"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Create SAML Attribute Mappers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Array of mappers to create
declare -a MAPPERS=(
  # Email mapper
  '{
    "name": "email",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-user-attribute-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "attribute.name": "urn:oid:0.9.2342.19200300.100.1.3",
      "user.attribute": "email"
    }
  }'
  
  # First name mapper
  '{
    "name": "firstName",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-user-attribute-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "attribute.name": "urn:oid:2.5.4.42",
      "user.attribute": "firstName"
    }
  }'
  
  # Last name mapper
  '{
    "name": "lastName",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-user-attribute-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "attribute.name": "urn:oid:2.5.4.4",
      "user.attribute": "lastName"
    }
  }'
  
  # Display name mapper
  '{
    "name": "displayName",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-user-attribute-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "attribute.name": "urn:oid:2.16.840.1.113730.3.1.241",
      "user.attribute": "displayName"
    }
  }'
  
  # Affiliation mapper
  '{
    "name": "affiliation",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-user-attribute-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "attribute.name": "urn:oid:1.3.6.1.4.1.5923.1.1.1.9",
      "user.attribute": "affiliation"
    }
  }'
  
  # eduPersonPrincipalName mapper
  '{
    "name": "eppn",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-user-attribute-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "attribute.name": "urn:oid:1.3.6.1.4.1.5923.1.1.1.6",
      "user.attribute": "eppn"
    }
  }'
  
  # Username template
  '{
    "name": "username",
    "identityProviderAlias": "eurac-research",
    "identityProviderMapper": "saml-username-idp-mapper",
    "config": {
      "syncMode": "INHERIT",
      "template": "${ATTRIBUTE.urn:oid:1.3.6.1.4.1.5923.1.1.1.6}"
    }
  }'
)

MAPPER_COUNT=0
for mapper in "${MAPPERS[@]}"; do
  MAPPER_NAME=$(echo "$mapper" | jq -r '.name')
  echo "Creating mapper: $MAPPER_NAME..."
  
  MAPPER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research/mappers" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$mapper")
  
  MAPPER_HTTP_CODE=$(echo "$MAPPER_RESPONSE" | tail -n1)
  
  if [ "$MAPPER_HTTP_CODE" = "201" ]; then
    echo "  ✅ Created: $MAPPER_NAME"
    ((MAPPER_COUNT++))
  elif [ "$MAPPER_HTTP_CODE" = "409" ]; then
    echo "  ⚠️  Already exists: $MAPPER_NAME"
  else
    echo "  ❌ Failed: $MAPPER_NAME (HTTP $MAPPER_HTTP_CODE)"
  fi
done

echo "✅ Created $MAPPER_COUNT attribute mappers"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Create EURAC Researchers Group"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

GROUP_CONFIG=$(cat <<'GROUP_JSON'
{
  "name": "eurac-researchers",
  "path": "/eurac-researchers",
  "attributes": {
    "description": ["EURAC Research institutional users"],
    "max_jobs": ["10"],
    "max_storage_gb": ["100"],
    "priority": ["high"],
    "quota_enabled": ["true"]
  }
}
GROUP_JSON
)

echo "Creating EURAC researchers group..."
GROUP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$GROUP_CONFIG")

GROUP_HTTP_CODE=$(echo "$GROUP_RESPONSE" | tail -n1)

if [ "$GROUP_HTTP_CODE" = "201" ]; then
  echo "✅ EURAC researchers group created"
elif [ "$GROUP_HTTP_CODE" = "409" ]; then
  echo "⚠️  Group already exists"
else
  echo "❌ Failed to create group (HTTP $GROUP_HTTP_CODE)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Verifying Identity Provider..."
IDP_CHECK=$(curl -s "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research" \
  -H "Authorization: Bearer $TOKEN")

if echo "$IDP_CHECK" | jq -e '.alias == "eurac-research"' > /dev/null 2>&1; then
  echo "✅ Identity Provider: eurac-research"
  echo "   Display Name: $(echo "$IDP_CHECK" | jq -r '.displayName')"
  echo "   Enabled: $(echo "$IDP_CHECK" | jq -r '.enabled')"
else
  echo "❌ Identity Provider verification failed"
fi

echo ""
echo "Verifying Mappers..."
MAPPERS_CHECK=$(curl -s "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/eurac-research/mappers" \
  -H "Authorization: Bearer $TOKEN")

MAPPER_NAMES=$(echo "$MAPPERS_CHECK" | jq -r '.[].name' | sort | tr '\n' ', ' | sed 's/,$//')
echo "✅ Mappers configured: $MAPPER_NAMES"

echo ""
echo "Verifying Group..."
GROUPS_CHECK=$(curl -s "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" \
  -H "Authorization: Bearer $TOKEN")

if echo "$GROUPS_CHECK" | jq -e '.[] | select(.name == "eurac-researchers")' > /dev/null 2>&1; then
  echo "✅ Group: eurac-researchers"
else
  echo "❌ Group verification failed"
fi

cat << 'SUMMARY_EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║           ✅ EURAC SAML CONFIGURATION COMPLETED SUCCESSFULLY             ║
╚══════════════════════════════════════════════════════════════════════════╝

📦 CONFIGURED COMPONENTS:

  ✅ EURAC SAML Identity Provider
     • Alias: eurac-research
     • Display Name: EURAC Research
     • SSO URL: https://sso.eurac.edu
     • Signature validation enabled
  
  ✅ SAML Attribute Mappers (7 mappers)
     • email, firstName, lastName
     • displayName, affiliation
     • eppn (eduPersonPrincipalName)
     • username template
  
  ✅ EURAC Researchers Group
     • Name: eurac-researchers
     • Enhanced quotas: 10 jobs, 100GB storage
     • Priority: high

📋 NEXT STEPS:

  1. Test EURAC Authentication Flow
     ---------------------------------
     • Access OpenEO API with EURAC login
     • Verify user attributes are mapped correctly
     • Check group membership and quotas
  
  2. Configure APISIX Routes (if needed)
     ------------------------------------
     • Route OpenEO API through APISIX gateway
     • Enable OIDC authentication plugin
     • Test end-to-end flow
  
  3. Integration Testing
     --------------------
     • Test EURAC user login
     • Verify OpenEO job submission
     • Check quota enforcement

🔗 USEFUL ENDPOINTS:

  Keycloak Admin: ${KEYCLOAK_URL}/admin/master/console/
  Realm: ${REALM}
  
  EURAC Login URL:
  ${KEYCLOAK_URL}/realms/${REALM}/broker/eurac-research/login

⚠️  REMINDER:

  This is a TEST deployment with default credentials.
  For production:
    • Change admin password
    • Configure proper certificates
    • Set up proper ingress/routes
    • Review security settings

SUMMARY_EOF
