# 🔐 EURAC Authentication Configuration for OpenEO
## EURAC Research SAML Integration via Keycloak

---

## EXECUTIVE SUMMARY

This document provides a comprehensive guide for configuring **EURAC Research** authentication for OpenEO-ArgoWorkflows through the EOEPCA Keycloak instance. EURAC uses SAML-based authentication through the eduGAIN federation, which can be integrated with Keycloak as a SAML Identity Provider.

**Key Points:**
- ✅ **EURAC IdP**: SAML-based authentication via eduGAIN
- ✅ **Federation**: eduGAIN member institution
- ✅ **Integration Method**: Keycloak SAML Identity Brokering
- ✅ **Entity ID**: https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php
- ✅ **Access**: EURAC staff and affiliates can login with institutional credentials

---

## TABLE OF CONTENTS

1. [EURAC Overview](#1-eurac-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Keycloak SAML Configuration](#4-keycloak-saml-configuration)
5. [Crossplane SAML Identity Provider](#5-crossplane-saml-identity-provider)
6. [User Attribute Mapping](#6-user-attribute-mapping)
7. [Group Mapping](#7-group-mapping)
8. [Testing EURAC Login](#8-testing-eurac-login)
9. [Troubleshooting](#9-troubleshooting)
10. [Production Deployment](#10-production-deployment)

---

## 1. EURAC OVERVIEW

### 1.1 EURAC Research Identity Provider

**Institution:** European Academy of Bozen/Bolzano (EURAC Research)
- **Location:** Bolzano/Bozen, Italy
- **Type:** Research Institution
- **Federation:** eduGAIN, IDEM (Italian eduGAIN Federation)
- **Protocol:** SAML 2.0

**EURAC SAML Endpoints:**
```
Entity ID: https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php
SSO URL: https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php
Metadata URL: https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php
```

---

### 1.2 Why EURAC for OpenEO?

EURAC Research is a key partner in Earth Observation research:
- 🛰️ **Remote Sensing**: Alpine monitoring and analysis
- 🌍 **EO Applications**: Environmental research
- 📊 **Data Processing**: Large-scale geospatial analysis
- 🔬 **Research Projects**: EU-funded EO initiatives

**Use Case:** EURAC researchers need to access OpenEO platform for processing satellite imagery and running EO workflows.

---

## 2. ARCHITECTURE

### 2.1 Authentication Flow

```
┌─────────────────┐
│  EURAC User     │
│  (Researcher)   │
└────────┬────────┘
         │ 1. Access OpenEO
         ▼
┌─────────────────────────┐
│  OpenEO Web UI          │
│  (OpenEO Editor)        │
└────────┬────────────────┘
         │ 2. Click "Login with EURAC"
         ▼
┌─────────────────────────┐
│  EOEPCA Keycloak        │
│  Realm: eoepca          │
│  - SAML IdP Broker      │
└────────┬────────────────┘
         │ 3. SAML AuthnRequest
         ▼
┌─────────────────────────┐
│  EURAC SSO              │
│  sso.eurac.edu          │
│  - SAML 2.0 IdP         │
└────────┬────────────────┘
         │ 4. User authenticates
         │    (EURAC credentials)
         ▼
         │ 5. SAML Response
         │    (with attributes)
         ▼
┌─────────────────────────┐
│  EOEPCA Keycloak        │
│  - Maps SAML attrs      │
│  - Creates/updates user │
│  - Assigns groups       │
└────────┬────────────────┘
         │ 6. OIDC JWT Token
         ▼
┌─────────────────────────┐
│  APISIX Gateway         │
│  - Validates JWT        │
│  - Enforces policies    │
└────────┬────────────────┘
         │ 7. Authorized request
         ▼
┌─────────────────────────┐
│  OpenEO API             │
│  - Process graphs       │
│  - Job execution        │
└─────────────────────────┘
```

---

### 2.2 Component Overview

| Component | Role | Configuration |
|-----------|------|---------------|
| **EURAC SSO** | SAML Identity Provider | External (managed by EURAC) |
| **Keycloak** | SAML-to-OIDC Bridge | SAML Identity Broker config |
| **APISIX** | API Gateway | OIDC authentication plugin |
| **OpenEO API** | Application | Receives validated JWT |
| **OPA** | Authorization | Policy enforcement (optional) |

---

## 3. PREREQUISITES

### 3.1 Requirements

Before configuring EURAC authentication:

- ✅ **Keycloak Running**: IAM Building Block deployed
- ✅ **Realm Created**: `eoepca` realm exists
- ✅ **Crossplane Enabled**: For declarative IdP configuration
- ✅ **EURAC SP Registration**: OpenEO registered with EURAC (optional but recommended)
- ✅ **SSL Certificates**: Valid TLS for Keycloak endpoints

---

### 3.2 Verify Keycloak

```bash
# Check Keycloak is running
kubectl get pods -n iam -l app.kubernetes.io/name=keycloak

# Verify realm exists
kubectl get realm -n iam eoepca

# Check Crossplane provider is configured
kubectl get providerconfig -n iam iam-keycloak-keycloak-provider-config
```

---

### 3.3 EURAC Metadata

Download EURAC SAML metadata:

```bash
# Download EURAC IdP metadata
curl -o eurac-idp-metadata.xml \
  https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php

# Verify metadata
xmllint --format eurac-idp-metadata.xml | head -30
```

**Expected Entity ID:**
```xml
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata"
                  entityID="https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php">
```

---

## 4. KEYCLOAK SAML CONFIGURATION

### 4.1 Manual Configuration (Via Keycloak Admin UI)

#### Step 1: Access Keycloak Admin Console

```bash
# Get Keycloak admin password
ADMIN_PASSWORD=$(kubectl get secret iam-keycloak -n iam \
  -o jsonpath='{.data.admin-password}' | base64 -d)

# Port forward
kubectl port-forward -n iam svc/iam-keycloak 8080:80

# Open browser: http://localhost:8080
# Login: admin / $ADMIN_PASSWORD
```

---

#### Step 2: Create SAML Identity Provider

1. Navigate to: **Realm: eoepca** → **Identity Providers** → **Add provider** → **SAML v2.0**

2. **General Settings:**
   - **Alias:** `eurac-research`
   - **Display Name:** `EURAC Research`
   - **Enabled:** ON
   - **Trust Email:** ON
   - **First Login Flow:** `first broker login`

3. **SAML Settings:**
   - **Service Provider Entity ID:** `https://iam-auth.develop.eoepca.org/realms/eoepca`
   - **Single Sign-On Service URL:** `https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php`
   - **Single Logout Service URL:** *(leave empty if not supported)*
   - **Backchannel Logout:** OFF
   - **Name ID Policy Format:** `urn:oasis:names:tc:SAML:2.0:nameid-format:persistent`
   - **Principal Type:** `Subject NameID`
   - **HTTP-POST Binding Response:** ON
   - **HTTP-POST Binding for AuthnRequest:** ON
   - **Want AuthnRequests Signed:** OFF (unless EURAC requires it)
   - **Want Assertions Signed:** ON
   - **Want Assertions Encrypted:** OFF
   - **Force Authentication:** OFF
   - **Validate Signature:** ON
   - **Use metadata descriptor URL:** ON
   - **Metadata Descriptor URL:** `https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php`
   - **Sync Mode:** `IMPORT` (or `FORCE` to always update user data)

4. **Save** and note the **Redirect URI** displayed (needed for EURAC SP registration)

---

#### Step 3: Configure Attribute Mappers

Create mappers to extract EURAC attributes:

**Mapper 1: Email**
- Name: `email`
- Sync Mode Override: `inherit`
- Mapper Type: `Attribute Importer`
- Attribute Name: `urn:oid:0.9.2342.19200300.100.1.3` (or `mail`)
- Friendly Name: `mail`
- User Attribute Name: `email`

**Mapper 2: First Name**
- Name: `firstName`
- Mapper Type: `Attribute Importer`
- Attribute Name: `urn:oid:2.5.4.42` (or `givenName`)
- Friendly Name: `givenName`
- User Attribute Name: `firstName`

**Mapper 3: Last Name**
- Name: `lastName`
- Mapper Type: `Attribute Importer`
- Attribute Name: `urn:oid:2.5.4.4` (or `sn`)
- Friendly Name: `sn`
- User Attribute Name: `lastName`

**Mapper 4: EURAC Affiliation**
- Name: `euracAffiliation`
- Mapper Type: `Attribute Importer`
- Attribute Name: `urn:oid:1.3.6.1.4.1.5923.1.1.1.9` (eduPersonScopedAffiliation)
- Friendly Name: `eduPersonScopedAffiliation`
- User Attribute Name: `affiliation`

**Mapper 5: Username**
- Name: `username`
- Mapper Type: `Username Template Importer`
- Template: `${NAMEID}@eurac.edu`
- Target: `BROKER_USERNAME`

---

## 5. CROSSPLANE SAML IDENTITY PROVIDER

### 5.1 Declarative Configuration (GitOps)

Create: `argocd/eoepca/openeo-argoworkflows/parts/keycloak-idp-eurac.yaml`

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: IdentityProvider
metadata:
  name: eurac-research-saml
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    
    # Identity Provider basic configuration
    alias: eurac-research
    displayName: "EURAC Research"
    enabled: true
    providerId: saml
    
    # Trust and flow settings
    trustEmail: true
    storeToken: false
    addReadTokenRoleOnCreate: false
    linkOnly: false
    firstBrokerLoginFlowAlias: "first broker login"
    
    # SAML-specific configuration
    config:
      # EURAC SAML IdP endpoints
      singleSignOnServiceUrl: "https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php"
      singleLogoutServiceUrl: ""
      
      # Metadata
      metadataDescriptorUrl: "https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php"
      useMetadataDescriptorUrl: "true"
      
      # Entity IDs
      entityId: "https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php"
      
      # Binding and signature settings
      postBindingResponse: "true"
      postBindingAuthnRequest: "true"
      wantAuthnRequestsSigned: "false"
      wantAssertionsSigned: "true"
      wantAssertionsEncrypted: "false"
      forceAuthn: "false"
      validateSignature: "true"
      signSpMetadata: "false"
      
      # NameID settings
      nameIDPolicyFormat: "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
      principalType: "SUBJECT"
      principalAttribute: ""
      
      # Synchronization
      syncMode: "IMPORT"
      
      # backchannel logout
      backchannelSupported: "false"
      
    # Attribute Mappers
    mappers:
      # Email mapper
      - name: email
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-user-attribute-idp-mapper
        config:
          syncMode: "INHERIT"
          attribute.name: "urn:oid:0.9.2342.19200300.100.1.3"
          attribute.friendly.name: "mail"
          user.attribute: "email"
          
      # First name mapper
      - name: firstName
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-user-attribute-idp-mapper
        config:
          syncMode: "INHERIT"
          attribute.name: "urn:oid:2.5.4.42"
          attribute.friendly.name: "givenName"
          user.attribute: "firstName"
          
      # Last name mapper
      - name: lastName
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-user-attribute-idp-mapper
        config:
          syncMode: "INHERIT"
          attribute.name: "urn:oid:2.5.4.4"
          attribute.friendly.name: "sn"
          user.attribute: "lastName"
          
      # Display name mapper
      - name: displayName
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-user-attribute-idp-mapper
        config:
          syncMode: "INHERIT"
          attribute.name: "urn:oid:2.16.840.1.113730.3.1.241"
          attribute.friendly.name: "displayName"
          user.attribute: "displayName"
          
      # eduPerson Affiliation
      - name: affiliation
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-user-attribute-idp-mapper
        config:
          syncMode: "INHERIT"
          attribute.name: "urn:oid:1.3.6.1.4.1.5923.1.1.1.9"
          attribute.friendly.name: "eduPersonScopedAffiliation"
          user.attribute: "affiliation"
          
      # eduPerson Principal Name (username)
      - name: eppn
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-user-attribute-idp-mapper
        config:
          syncMode: "INHERIT"
          attribute.name: "urn:oid:1.3.6.1.4.1.5923.1.1.1.6"
          attribute.friendly.name: "eduPersonPrincipalName"
          user.attribute: "eppn"
          
      # Username template mapper
      - name: username
        identityProviderAlias: eurac-research
        identityProviderMapper: saml-username-idp-mapper
        config:
          syncMode: "INHERIT"
          template: "${NAMEID}@eurac"
          
  providerConfigRef:
    name: iam-keycloak-keycloak-provider-config
```

---

### 5.2 Apply EURAC Identity Provider

```bash
# Navigate to OpenEO ArgoWorkflows directory
cd argocd/eoepca/openeo-argoworkflows

# Apply the Identity Provider configuration
kubectl apply -f parts/keycloak-idp-eurac.yaml

# Wait for IdP to be ready
kubectl wait --for=condition=Ready \
  identityprovider/eurac-research-saml -n iam --timeout=300s

# Verify creation
kubectl get identityprovider -n iam
```

---

### 5.3 Get Service Provider Metadata

After creating the IdP, get the SP metadata to register with EURAC (if required):

```bash
# Get Keycloak SP metadata for EURAC
curl -s https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor \
  | xmllint --format - > eoepca-sp-metadata.xml

# Key information to share with EURAC:
# - Entity ID: https://iam-auth.develop.eoepca.org/realms/eoepca
# - ACS URL: https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint
# - Metadata URL: https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor
```

---

## 6. USER ATTRIBUTE MAPPING

### 6.1 SAML Attributes from EURAC

EURAC typically provides these SAML attributes (via eduGAIN):

| SAML Attribute (OID) | Friendly Name | Description | Example |
|---------------------|---------------|-------------|---------|
| `urn:oid:0.9.2342.19200300.100.1.3` | `mail` | Email address | `john.doe@eurac.edu` |
| `urn:oid:2.5.4.42` | `givenName` | First name | `John` |
| `urn:oid:2.5.4.4` | `sn` | Last name | `Doe` |
| `urn:oid:2.16.840.1.113730.3.1.241` | `displayName` | Display name | `John Doe` |
| `urn:oid:1.3.6.1.4.1.5923.1.1.1.6` | `eduPersonPrincipalName` | Unique ID | `john.doe@eurac.edu` |
| `urn:oid:1.3.6.1.4.1.5923.1.1.1.9` | `eduPersonScopedAffiliation` | Role/Status | `staff@eurac.edu` |
| `urn:oid:1.3.6.1.4.1.5923.1.1.1.1` | `eduPersonAffiliation` | Affiliation | `staff`, `faculty`, `student` |

---

### 6.2 Mapping to Keycloak User Attributes

Keycloak maps SAML attributes to user profile:

```yaml
# SAML Attribute → Keycloak User Attribute
mail → email
givenName → firstName
sn → lastName
displayName → displayName (custom)
eduPersonPrincipalName → eppn (custom)
eduPersonScopedAffiliation → affiliation (custom)
```

---

### 6.3 Custom Attribute Propagation to JWT

To include EURAC attributes in JWT tokens for OpenEO, configure client scopes:

Create: `argocd/eoepca/openeo-argoworkflows/parts/keycloak-eurac-scope.yaml`

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: ClientScope
metadata:
  name: eurac-attributes
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: eurac-attributes
    description: "EURAC user attributes for OpenEO"
    protocol: openid-connect
    attributes:
      include.in.token.scope: "true"
      display.on.consent.screen: "false"
    
    protocolMappers:
      # Map EURAC affiliation to JWT
      - name: eurac-affiliation
        protocol: openid-connect
        protocolMapper: oidc-usermodel-attribute-mapper
        config:
          user.attribute: affiliation
          claim.name: eurac_affiliation
          jsonType.label: String
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          
      # Map EURAC ePPN to JWT
      - name: eurac-eppn
        protocol: openid-connect
        protocolMapper: oidc-usermodel-attribute-mapper
        config:
          user.attribute: eppn
          claim.name: eurac_eppn
          jsonType.label: String
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          
      # Mark as EURAC user
      - name: identity-provider
        protocol: openid-connect
        protocolMapper: oidc-hardcoded-claim-mapper
        config:
          claim.name: identity_provider
          claim.value: eurac-research
          jsonType.label: String
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          
  providerConfigRef:
    name: iam-keycloak-keycloak-provider-config
```

---

## 7. GROUP MAPPING

### 7.1 Automatic Group Assignment

Assign EURAC users to specific OpenEO groups based on affiliation:

Create: `argocd/eoepca/openeo-argoworkflows/parts/keycloak-eurac-group-mapper.yaml`

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: IdentityProviderMapper
metadata:
  name: eurac-staff-group-mapper
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    identityProviderAlias: eurac-research
    name: eurac-staff-to-openeo-users
    identityProviderMapper: saml-advanced-role-idp-mapper
    
    config:
      syncMode: "INHERIT"
      # Match staff affiliation
      attribute.name: "urn:oid:1.3.6.1.4.1.5923.1.1.1.1"
      attribute.friendly.name: "eduPersonAffiliation"
      attribute.value: "staff"
      # Assign to group
      role: "openeo-users"
      are.role.values.regex: "false"
      
  providerConfigRef:
    name: iam-keycloak-keycloak-provider-config

---
apiVersion: keycloak.crossplane.io/v1alpha1
kind: IdentityProviderMapper
metadata:
  name: eurac-faculty-group-mapper
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    identityProviderAlias: eurac-research
    name: eurac-faculty-to-openeo-premium
    identityProviderMapper: saml-advanced-role-idp-mapper
    
    config:
      syncMode: "INHERIT"
      # Match faculty affiliation
      attribute.name: "urn:oid:1.3.6.1.4.1.5923.1.1.1.1"
      attribute.friendly.name: "eduPersonAffiliation"
      attribute.value: "faculty"
      # Assign to premium group
      role: "openeo-premium-users"
      are.role.values.regex: "false"
      
  providerConfigRef:
    name: iam-keycloak-keycloak-provider-config
```

---

### 7.2 Create EURAC-specific Groups

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Group
metadata:
  name: eurac-researchers
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: eurac-researchers
    path: /organizations/eurac
    attributes:
      organization: ["eurac"]
      organization_name: ["EURAC Research"]
      max_concurrent_jobs: ["10"]
      max_storage_gb: ["100"]
      
  providerConfigRef:
    name: iam-keycloak-keycloak-provider-config
```

---

## 8. TESTING EURAC LOGIN

### 8.1 Test Login Flow

```bash
# 1. Get Keycloak OIDC discovery
curl -s https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/openid-configuration \
  | jq '.authorization_endpoint'

# Expected output:
# "https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/auth"

# 2. Construct login URL with EURAC hint
REDIRECT_URI="https://openeo-api.develop.eoepca.org/callback"
CLIENT_ID="openeo-argoworkflows"
EURAC_LOGIN_URL="https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&response_type=code&scope=openid%20profile%20email&kc_idp_hint=eurac-research"

echo "EURAC Login URL:"
echo "$EURAC_LOGIN_URL"

# 3. Open in browser - should redirect to EURAC SSO
```

---

### 8.2 Verify User Creation

After successful EURAC login:

```bash
# List users in Keycloak
kubectl exec -n iam deployment/iam-keycloak -- \
  /opt/keycloak/bin/kcadm.sh get users -r eoepca \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password "${ADMIN_PASSWORD}" \
  | jq '.[] | select(.attributes.affiliation != null)'

# Check for EURAC-linked users
kubectl exec -n iam deployment/iam-keycloak -- \
  /opt/keycloak/bin/kcadm.sh get users -r eoepca \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password "${ADMIN_PASSWORD}" \
  | jq '.[] | select(.federatedIdentities[].identityProvider == "eurac-research")'
```

---

### 8.3 Decode JWT Token

After obtaining token from OpenEO:

```bash
# Get token via OpenEO authentication
TOKEN="<your-jwt-token>"

# Decode payload
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq

# Check for EURAC attributes
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '{
  sub,
  email,
  preferred_username,
  eurac_affiliation,
  eurac_eppn,
  identity_provider,
  groups
}'
```

Expected JWT claims:
```json
{
  "sub": "a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6",
  "email": "researcher@eurac.edu",
  "preferred_username": "researcher@eurac",
  "eurac_affiliation": "staff@eurac.edu",
  "eurac_eppn": "researcher@eurac.edu",
  "identity_provider": "eurac-research",
  "groups": ["/organizations/eurac", "/openeo/users"]
}
```

---

## 9. TROUBLESHOOTING

### 9.1 Common Issues

#### Issue 1: SAML Response Signature Validation Failed

**Symptoms:**
```
ERROR: SAML response signature validation failed
```

**Solution:**
```bash
# Check if EURAC metadata is properly loaded
# In Keycloak Admin UI:
# Identity Providers → eurac-research → Import from URL
# Metadata descriptor URL: https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php

# Or verify certificate manually
curl -s https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php \
  | xmllint --xpath '//*[local-name()="X509Certificate"]/text()' -
```

---

#### Issue 2: Attributes Not Received

**Symptoms:**
- User created but email/name is empty
- Custom attributes missing

**Solution:**
```bash
# Check SAML response in Keycloak logs
kubectl logs -n iam deployment/iam-keycloak -f | grep -i saml

# Common fixes:
# 1. Verify attribute OIDs match EURAC's released attributes
# 2. Check eduGAIN attribute release policy
# 3. Ensure EURAC has released attributes to your SP
```

**Contact EURAC IT:**
```
Email: it-support@eurac.edu
Request: Release eduPerson attributes for OpenEO SP
Metadata: https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor
```

---

#### Issue 3: Login Loop / Redirect Issues

**Symptoms:**
- Redirects back to Keycloak login page
- `kc_idp_hint` not working

**Solution:**
```bash
# Verify IdP alias is correct
kubectl get identityprovider eurac-research-saml -n iam -o yaml | grep alias

# Test without hint first
# Then add: ?kc_idp_hint=eurac-research
```

---

#### Issue 4: Users Not Assigned to Groups

**Symptoms:**
- EURAC users login successfully
- Not assigned to `openeo-users` group

**Solution:**
```yaml
# Check group mapper configuration
kubectl get identityprovidermapper -n iam

# Verify affiliation attribute is received
# May need to adjust attribute matching in mapper
```

---

### 9.2 Debug SAML Flow

Enable SAML tracer in browser:

1. Install **SAML-tracer** extension (Firefox/Chrome)
2. Open SAML tracer
3. Initiate EURAC login
4. Capture:
   - SAML AuthnRequest (from Keycloak → EURAC)
   - SAML Response (from EURAC → Keycloak)
5. Verify:
   - Destination URL matches
   - Assertions are signed
   - Attributes are present

---

### 9.3 Check Keycloak Events

```bash
# Enable events in Keycloak (if not already)
# Realm Settings → Events → Save Events: ON

# View events
kubectl exec -n iam deployment/iam-keycloak -- \
  /opt/keycloak/bin/kcadm.sh get events -r eoepca \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password "${ADMIN_PASSWORD}" \
  | jq '.[] | select(.type | contains("LOGIN"))'
```

---

## 10. PRODUCTION DEPLOYMENT

### 10.1 Update Kustomization

Add EURAC IdP to OpenEO kustomization:

`argocd/eoepca/openeo-argoworkflows/parts/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - helm-openeo-argoworkflows.yaml
  - apisixroute-openeo.yaml
  - ss-openeo-api-client.yaml
  - keycloak-idp-eurac.yaml           # ← Add this
  - keycloak-eurac-scope.yaml         # ← Add this
  - keycloak-eurac-group-mapper.yaml  # ← Add this
```

---

### 10.2 Deploy via ArgoCD

```bash
# Commit EURAC configuration
git add argocd/eoepca/openeo-argoworkflows/parts/keycloak-idp-eurac.yaml
git add argocd/eoepca/openeo-argoworkflows/parts/keycloak-eurac-scope.yaml
git add argocd/eoepca/openeo-argoworkflows/parts/keycloak-eurac-group-mapper.yaml
git add argocd/eoepca/openeo-argoworkflows/parts/kustomization.yaml

git commit -m "feat: add EURAC SAML authentication for OpenEO"
git push origin egi-checkin-investigation

# Sync ArgoCD application
argocd app sync openeo-argoworkflows

# Verify deployment
kubectl get identityprovider -n iam eurac-research-saml
kubectl get clientscope -n iam eurac-attributes
```

---

### 10.3 Update OpenEO Web Editor

Configure OpenEO Web Editor to show EURAC login option:

```yaml
# In OpenEO Web Editor configuration
oidc:
  providers:
    - id: "eoepca-eurac"
      issuer: "https://iam-auth.develop.eoepca.org/realms/eoepca"
      title: "EURAC Research Login"
      description: "Login with your EURAC credentials"
      hint: "eurac-research"  # kc_idp_hint parameter
      logo: "/logos/eurac.png"
```

---

### 10.4 Communication to Users

**Email Template:**

```
Subject: New EURAC Authentication for OpenEO Platform

Dear EURAC Researchers,

We're pleased to announce that you can now access the OpenEO Platform 
using your EURAC institutional credentials!

🔐 How to Login:
1. Go to: https://openeo-api.develop.eoepca.org
2. Click "Login with EURAC Research"
3. Use your EURAC username and password
4. You'll be automatically logged into OpenEO

✨ Benefits:
- Single sign-on with your EURAC account
- No need for separate credentials
- Automatic access to EURAC researcher quota

📊 Your Resources:
- Concurrent Jobs: 10
- Storage: 100 GB
- Priority processing for EURAC projects

For support, contact: openeo-support@eoepca.org

Best regards,
EOEPCA Team
```

---

## SUMMARY

✅ **Configuration Complete:**
- EURAC SAML IdP configured in Keycloak
- Attribute mapping for email, name, affiliation
- Automatic group assignment for EURAC users
- JWT tokens include EURAC-specific claims
- Ready for production deployment

✅ **Next Steps:**
1. Test with EURAC test account
2. Register SP with EURAC IT (if required)
3. Deploy to production
4. Monitor authentication logs
5. Gather user feedback

✅ **Access Pattern:**
```
EURAC User → Keycloak (SAML broker) → OpenEO API (OIDC) → Processing
```

---

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Author:** EOEPCA Team  
**Status:** ✅ Ready for Implementation
