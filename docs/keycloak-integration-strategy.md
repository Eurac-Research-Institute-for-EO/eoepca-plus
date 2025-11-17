# 🔐 KEYCLOAK INTEGRATION STRATEGY FOR OPENEO-ARGOWORKFLOWS
## Comprehensive Implementation Guide for EOEPCA Platform

---

## EXECUTIVE SUMMARY

This document outlines a comprehensive strategy for migrating OpenEO-ArgoWorkflows from EGI Check-in to a **local Keycloak instance** within the EOEPCA infrastructure, while maintaining compatibility with EGI Check-in as a federated identity provider. This approach provides greater control, customization, and alignment with the EOEPCA ecosystem.

**Key Benefits:**
- ✅ **Local Control**: Manage authentication policies and user flows
- ✅ **EOEPCA Integration**: Native integration with IAM Building Block
- ✅ **EGI Federation**: Maintain EGI Check-in as federated IdP
- ✅ **Policy Enforcement**: Leverage OPA for fine-grained authorization
- ✅ **Consistency**: Align with other EOEPCA services
- ✅ **Flexibility**: Custom user attributes and groups

---

## TABLE OF CONTENTS

1. [Architecture Overview](#1-architecture-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Keycloak in EOEPCA Ecosystem](#3-keycloak-in-eoepca-ecosystem)
4. [Proposed Architecture](#4-proposed-architecture)
5. [Implementation Strategy](#5-implementation-strategy)
6. [Technical Implementation](#6-technical-implementation)
7. [Configuration Details](#7-configuration-details)
8. [Security Considerations](#8-security-considerations)
9. [Migration Path](#9-migration-path)
10. [Deployment Guide](#10-deployment-guide)
11. [Testing & Validation](#11-testing--validation)
12. [Monitoring & Maintenance](#12-monitoring--maintenance)
13. [Rollback Strategy](#13-rollback-strategy)
14. [Future Enhancements](#14-future-enhancements)
15. [Appendices](#15-appendices)

---

## 1. ARCHITECTURE OVERVIEW

### 1.1 Current Architecture (EGI Check-in)

```
┌──────────────┐
│ EGI Check-in │ (External OIDC Provider)
│ aai.egi.eu   │
└──────┬───────┘
       │ JWT Token
       ▼
┌─────────────────────────┐
│ OpenEO API              │
│ - Validates JWT         │
│ - No policy enforcement │
└────────┬────────────────┘
         │
         ├──► PostgreSQL
         └──► Argo Workflows
```

**Limitations:**
- No control over user attributes
- Cannot enforce custom authorization policies
- No integration with EOEPCA IAM
- Limited user management capabilities
- No OPA integration for fine-grained access control

---

### 1.2 Proposed Architecture (Keycloak + EURAC + EGI Federation)

```
┌──────────────┐         ┌─────────────────┐
│ EURAC SSO    │────────►│   Keycloak      │
│ (SAML IdP)   │ SAML    │   (EOEPCA IAM)  │
└──────────────┘         │                 │
                         │ - Realm: eoepca │
┌──────────────┐         │ - User mgmt     │
│ EGI Check-in │────────►│ - Groups/Roles  │
│ (Fed. IdP)   │ OIDC    │ - Custom attrs  │
└──────────────┘         │                 │
                         │                 │
┌──────────────┐         │                 │
│ Other eduGAIN│────────►│                 │
│ IdPs         │ SAML    │                 │
└──────────────┘         └────────┬────────┘
                                  │ JWT with
                                  │ custom claims
                                  ▼
                         ┌─────────────────────┐
                         │  APISIX Gateway     │
                         │  - OIDC plugin      │
                         │  - Token validation │
                         └────────┬────────────┘
                                  │
                                  ▼
┌──────────┐             ┌─────────────────────┐
│   OPA    │◄────────────│ OpenEO API          │
│ Policies │  Query      │ - Process graphs    │
└──────────┘             │ - Job management    │
                         └────────┬────────────┘
                                  │
                                  ├──► PostgreSQL
                                  │    (User/Job data)
                                  │
                                  └──► Argo Workflows
                                       (Job execution)
```

**Advantages:**
- ✅ Centralized IAM with EOEPCA
- ✅ Fine-grained authorization via OPA
- ✅ Custom user attributes and claims
- ✅ Group-based access control
- ✅ Integration with other EOEPCA services
- ✅ Maintains EGI federation

---

## 2. CURRENT STATE ANALYSIS

### 2.1 Existing OpenEO Configuration

**Current OIDC Settings:**
```yaml
global:
  env:
    oidcUrl: "https://aai.egi.eu/auth/realms/egi"
    odicOrganisation: "egi"
    oidcPolicies: ""  # Empty = no policy enforcement
```

**Issues:**
1. **No Authorization Policies**: Empty `oidcPolicies` allows any EGI token
2. **External Dependency**: Relies entirely on external EGI service
3. **Limited Customization**: Cannot add custom claims or attributes
4. **No EOEPCA Integration**: Isolated from platform IAM
5. **Security Risk**: Hardcoded password in configuration

---

### 2.2 EOEPCA IAM Infrastructure

**Current IAM Components:**
- **Keycloak**: Version with OPA plugin (custom image)
- **PostgreSQL**: Database for Keycloak
- **OPA (Open Policy Agent)**: Authorization engine
- **OPAL**: Policy management
- **APISIX**: API Gateway with OIDC/authz plugins
- **Crossplane**: Infrastructure management

**Keycloak Image:**
```yaml
image:
  registry: byud8gih.c1.de1.container-registry.ovh.net
  repository: eoepca/keycloak-with-opa-plugin
  tag: 0.5.1
```

**Features:**
- OPA integration for policy-based authorization
- Realm: `eoepca`
- eduGAIN federation support
- Custom authentication flows
- Group and role management

---

## 3. KEYCLOAK IN EOEPCA ECOSYSTEM

### 3.1 Keycloak Deployment

**Helm Chart:** `iam-bb` (version 2.0.0-rc2.4)

**Components:**
```yaml
iam:
  keycloak:
    enabled: true
    url: https://iam-auth.develop.eoepca.org
    createRoute: true
    configuration:
      useCrossplane: true
      realm:
        name: eoepca
        displayName: EOEPCA
```

---

### 3.2 How Other Services Use Keycloak

#### Example 1: Workspace API

```yaml
# APISIX Route with OpenID Connect
plugins:
  - name: openid-connect
    enable: true
    config:
      discovery: "https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/openid-configuration"
      use_jwks: true
      bearer_only: false
      set_access_token_header: true
      access_token_in_authorization_header: true
    secretRef: workspace-api

  - name: authz-keycloak  # UMA authorization
    enable: true
    config:
      discovery: https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/uma2-configuration
      lazy_load_paths: true
    secretRef: workspace-api

  - name: opa  # Policy enforcement
    enable: true
    config:
      host: http://iam-opa.iam:8181
      policy: eoepca/workspace/wsapi
```

**Client Configuration (SealedSecret):**
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: workspace-api
  namespace: workspace
spec:
  encryptedData:
    client_id: <encrypted>
    client_secret: <encrypted>
```

---

#### Example 2: ZOO-DRU-WES

```yaml
plugins:
  - name: openid-connect
    config:
      client_id: "zoo"
      client_secret: "Fsw9DtGQ52lje15lQtPC8CDxhpwqE8Di"
      discovery: "https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/openid-configuration"

  - name: authz-keycloak
    config:
      client_id: "zoo"
      client_secret: "Fsw9DtGQ52lje15lQtPC8CDxhpwqE8Di"
      discovery: https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/uma2-configuration
```

---

#### Example 3: Application Quality (Grafana)

Uses OIDC for SSO:
```yaml
GF_AUTH_GENERIC_OAUTH_ENABLED: true
GF_AUTH_GENERIC_OAUTH_NAME: "Keycloak"
GF_AUTH_GENERIC_OAUTH_CLIENT_ID: <from-sealed-secret>
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: <from-sealed-secret>
GF_AUTH_GENERIC_OAUTH_AUTH_URL: https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/auth
GF_AUTH_GENERIC_OAUTH_TOKEN_URL: https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/token
```

---

## 4. PROPOSED ARCHITECTURE

### 4.1 Integration Approach

**Strategy:** **Hybrid Federation**
- **Primary IdP**: EOEPCA Keycloak (local)
- **Federated IdP**: EGI Check-in (external)
- **Authorization**: OPA policies
- **Gateway**: APISIX for routing and initial auth

---

### 4.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    EOEPCA Platform                          │
│                                                             │
│  ┌──────────────┐                                          │
│  │  Keycloak    │  ← Identity Provider                     │
│  │  (IAM BB)    │                                          │
│  │              │  Realms:                                 │
│  │  - eoepca    │  - Users, Groups, Roles                  │
│  │              │  - OpenEO client registration            │
│  └──────┬───────┘  - EGI federation config                 │
│         │                                                   │
│         │ OIDC Discovery                                    │
│         │                                                   │
│  ┌──────▼───────┐                                          │
│  │   APISIX     │  ← API Gateway                           │
│  │   Gateway    │                                          │
│  │              │  Plugins:                                │
│  │  Plugins:    │  - openid-connect                        │
│  │  - OIDC      │  - authz-keycloak (UMA2)                 │
│  │  - authz-kc  │  - opa (optional, fine-grained)          │
│  │  - opa       │                                          │
│  └──────┬───────┘                                          │
│         │                                                   │
│         │ Validated Request                                │
│         │ + JWT Claims                                     │
│         ▼                                                   │
│  ┌────────────────────────┐                                │
│  │  OpenEO API            │  ← Application                 │
│  │  (ArgoWorkflows)       │                                │
│  │                        │  Receives:                     │
│  │  - Process graphs      │  - Validated JWT               │
│  │  - Job management      │  - User info in headers        │
│  │  - User workspaces     │  - Authorization decision      │
│  └────────┬───────────────┘                                │
│           │                                                 │
│           ├──► PostgreSQL (User/Job DB)                    │
│           │                                                 │
│           └──► Argo Workflows (Execution)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘

External Federation:
┌──────────────┐
│ EURAC SSO    │ ──SAML────────► Keycloak (Primary Identity Provider)
└──────────────┘

┌──────────────┐
│ EGI Check-in │ ──OIDC────────► Keycloak (Identity Brokering)
└──────────────┘

┌──────────────┐
│ Other eduGAIN│ ──SAML────────► Keycloak (SAML federation)
│ IdPs         │
└──────────────┘
```

---

## 5. IMPLEMENTATION STRATEGY

### 5.1 Implementation Phases

#### Phase 1: Preparation (Week 1)
- [ ] Audit current EGI Check-in integration
- [ ] Document OpenEO API authentication flow
- [ ] Review EOEPCA Keycloak configuration
- [ ] Create OpenEO client in Keycloak
- [ ] Configure test realm/environment

#### Phase 2: Keycloak Configuration (Week 2)
- [ ] Register OpenEO client in `eoepca` realm
- [ ] Configure client scopes and mappers
- [ ] Set up service account for OpenEO
- [ ] Configure EGI Check-in as Identity Broker
- [ ] Create OpenEO user groups and roles

#### Phase 3: APISIX Integration (Week 3)
- [ ] Create APISIX route for OpenEO
- [ ] Configure `openid-connect` plugin
- [ ] Configure `authz-keycloak` plugin (optional)
- [ ] Set up OPA policies for OpenEO
- [ ] Create SealedSecrets for credentials

#### Phase 4: OpenEO API Modification (Week 4)
- [ ] Update OIDC configuration to Keycloak
- [ ] Implement token validation logic
- [ ] Add policy enforcement (if using OPA)
- [ ] Update user management for Keycloak
- [ ] Add group/role based features

#### Phase 5: Testing (Week 5)
- [ ] Unit tests for authentication
- [ ] Integration tests with Keycloak
- [ ] End-to-end workflow tests
- [ ] Performance testing
- [ ] Security audit

#### Phase 6: Deployment (Week 6)
- [ ] Deploy to development environment
- [ ] Validate with test users
- [ ] Monitor logs and metrics
- [ ] Fix issues and iterate
- [ ] Deploy to production

#### Phase 7: Migration & Documentation (Week 7)
- [ ] Migrate existing EGI users
- [ ] Update user documentation
- [ ] Create admin guides
- [ ] Training for operators
- [ ] Decommission EGI direct integration

---

### 5.2 Decision Matrix

| Aspect | EGI Check-in Direct | Keycloak + EGI Federation |
|--------|---------------------|---------------------------|
| **Control** | ❌ External only | ✅ Full local control |
| **Custom Claims** | ❌ Limited | ✅ Fully customizable |
| **EOEPCA Integration** | ❌ None | ✅ Native |
| **Authorization** | ⚠️ Basic | ✅ OPA + UMA2 |
| **User Management** | ❌ External | ✅ Local + federated |
| **Maintenance** | ✅ Low | ⚠️ Medium |
| **Setup Complexity** | ✅ Simple | ⚠️ Complex |
| **Flexibility** | ❌ Low | ✅ High |
| **EGI Compatibility** | ✅ Direct | ✅ Federated |

**Recommendation:** ✅ **Keycloak + EGI Federation**

---

## 6. TECHNICAL IMPLEMENTATION

### 6.1 Keycloak Client Registration

#### Step 1: Create OpenEO Client via Crossplane

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Client
metadata:
  name: openeo-argoworkflows
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    clientId: openeo-argoworkflows
    name: "OpenEO ArgoWorkflows API"
    description: "OpenEO API with Argo Workflows backend"
    enabled: true
    protocol: openid-connect
    publicClient: false
    serviceAccountsEnabled: true
    authorizationServicesEnabled: true
    
    # OAuth2 flows
    standardFlowEnabled: true
    implicitFlowEnabled: false
    directAccessGrantsEnabled: true
    
    # URLs
    rootUrl: "https://openeo-api.develop.eoepca.org"
    baseUrl: "/"
    redirectUris:
      - "https://openeo-api.develop.eoepca.org/*"
      - "https://openeo-api.develop.eoepca.org/openeo/*"
    webOrigins:
      - "https://openeo-api.develop.eoepca.org"
    
    # Attributes
    attributes:
      access.token.lifespan: "3600"
      pkce.code.challenge.method: "S256"
      
    # Default client scopes
    defaultClientScopes:
      - openid
      - profile
      - email
      - roles
      - groups
      
  providerConfigRef:
    name: iam-keycloak-keycloak-provider-config
```

---

#### Step 2: Configure Client Scopes

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: ClientScope
metadata:
  name: openeo-scope
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: openeo
    description: "OpenEO specific claims"
    protocol: openid-connect
    attributes:
      include.in.token.scope: "true"
      display.on.consent.screen: "false"
    protocolMappers:
      - name: openeo-username
        protocol: openid-connect
        protocolMapper: oidc-usermodel-property-mapper
        config:
          user.attribute: username
          claim.name: preferred_username
          jsonType.label: String
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          
      - name: openeo-groups
        protocol: openid-connect
        protocolMapper: oidc-group-membership-mapper
        config:
          claim.name: groups
          full.path: "false"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
          
      - name: openeo-roles
        protocol: openid-connect
        protocolMapper: oidc-usermodel-realm-role-mapper
        config:
          claim.name: roles
          jsonType.label: String
          multivalued: "true"
          id.token.claim: "true"
          access.token.claim: "true"
          userinfo.token.claim: "true"
```

---

#### Step 3: Create Service Account & Roles

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Role
metadata:
  name: openeo-admin
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: openeo-admin
    description: "OpenEO Administrator"
    
---
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Role
metadata:
  name: openeo-user
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: openeo-user
    description: "OpenEO Regular User"
    
---
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Role
metadata:
  name: openeo-job-executor
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: openeo-job-executor
    description: "Can execute OpenEO jobs"
```

---

#### Step 4: Create OpenEO Groups

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Group
metadata:
  name: openeo-users
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: openeo-users
    path: /openeo/users
    
---
apiVersion: keycloak.crossplane.io/v1alpha1
kind: Group
metadata:
  name: openeo-premium-users
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    name: openeo-premium-users
    path: /openeo/premium
    attributes:
      max_concurrent_jobs: ["10"]
      max_storage_gb: ["100"]
```

---

### 6.2 EGI Check-in Federation

#### Configure Identity Broker

```yaml
apiVersion: keycloak.crossplane.io/v1alpha1
kind: IdentityProvider
metadata:
  name: egi-checkin
  namespace: iam
spec:
  forProvider:
    realmRef:
      name: eoepca
    alias: egi-checkin
    providerId: oidc
    displayName: "EGI Check-in"
    enabled: true
    trustEmail: true
    storeToken: false
    addReadTokenRoleOnCreate: false
    firstBrokerLoginFlowAlias: "first broker login"
    
    config:
      clientId: "eoepca-openeo"  # Register with EGI
      clientSecret: "<from-sealed-secret>"
      authorizationUrl: "https://aai.egi.eu/auth/realms/egi/protocol/openid-connect/auth"
      tokenUrl: "https://aai.egi.eu/auth/realms/egi/protocol/openid-connect/token"
      userInfoUrl: "https://aai.egi.eu/auth/realms/egi/protocol/openid-connect/userinfo"
      jwksUrl: "https://aai.egi.eu/auth/realms/egi/protocol/openid-connect/certs"
      issuer: "https://aai.egi.eu/auth/realms/egi"
      useJwksUrl: "true"
      validateSignature: "true"
      defaultScope: "openid profile email eduperson_entitlement"
      syncMode: "IMPORT"
```

---

### 6.3 APISIX Route Configuration

Create: `argocd/eoepca/openeo-argoworkflows/parts/apisixroute-openeo.yaml`

```yaml
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: openeo-api
  namespace: openeo
spec:
  http:
    # Public endpoints (no auth)
    - name: openeo-api-public
      match:
        hosts:
          - openeo-api.develop.eoepca.org
        paths:
          - /.well-known/*
          - /openeo/1.1.0/
          - /openeo/1.1.0/health
          - /metrics
      backends:
        - serviceName: openeo-openeo-argo
          servicePort: 8000
      plugins: []
      
    # Authenticated endpoints
    - name: openeo-api-auth
      match:
        hosts:
          - openeo-api.develop.eoepca.org
        paths:
          - /openeo/1.1.0/credentials/*
          - /openeo/1.1.0/me
          - /openeo/1.1.0/jobs
          - /openeo/1.1.0/jobs/*
          - /openeo/1.1.0/process_graphs
          - /openeo/1.1.0/process_graphs/*
          - /openeo/1.1.0/files
          - /openeo/1.1.0/files/*
      backends:
        - serviceName: openeo-openeo-argo
          servicePort: 8000
      plugins:
        - name: openid-connect
          enable: true
          config:
            discovery: "https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/openid-configuration"
            realm: "eoepca"
            use_jwks: true
            bearer_only: true
            set_access_token_header: true
            access_token_in_authorization_header: true
            set_id_token_header: true
            set_userinfo_header: true
          secretRef: openeo-api-client
          
        # Optional: OPA policy enforcement
        - name: opa
          enable: true
          config:
            host: http://iam-opa.iam:8181
            policy: eoepca/openeo/api
            with_route: true
            
    # Admin endpoints (UMA2 authorization)
    - name: openeo-api-admin
      match:
        hosts:
          - openeo-api.develop.eoepca.org
        paths:
          - /openeo/1.1.0/admin/*
      backends:
        - serviceName: openeo-openeo-argo
          servicePort: 8000
      plugins:
        - name: authz-keycloak
          enable: true
          config:
            discovery: https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/uma2-configuration
            lazy_load_paths: true
            ssl_verify: false
          secretRef: openeo-api-client
```

---

### 6.4 SealedSecret for Client Credentials

Create script: `argocd/eoepca/openeo-argoworkflows/ss-openeo-client.sh`

```bash
#!/usr/bin/env bash

ORIG_DIR="$(pwd)"
cd "$(dirname "$0")"
BIN_DIR="$(pwd)"

onExit() {
  cd "${ORIG_DIR}"
}
trap onExit EXIT

# Optional local .env file for secret values
source .env 2>/dev/null

SECRET_NAME="openeo-api-client"
NAMESPACE="openeo"

OPENEO_CLIENT_ID="${1:-${OPENEO_CLIENT_ID:-openeo-argoworkflows}}"
OPENEO_CLIENT_SECRET="${2:-${OPENEO_CLIENT_SECRET:-changeme}}"

secretYaml() {
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="client_id=${OPENEO_CLIENT_ID}" \
    --from-literal="client_secret=${OPENEO_CLIENT_SECRET}" \
    --dry-run=client -o yaml
}

# Create Secret and pipe to kubeseal
secretYaml \
  | kubeseal -o yaml --controller-name sealed-secrets --controller-namespace infra \
  > parts/ss-${SECRET_NAME}.yaml

echo "✅ Created SealedSecret: parts/ss-${SECRET_NAME}.yaml"
```

---

### 6.5 OpenEO API Configuration Update

Update `helm-openeo-argoworkflows.yaml`:

```yaml
helm:
  releaseName: openeo
  valuesObject:
    global:
      env:
        # OLD: EGI Check-in
        # oidcUrl: "https://aai.egi.eu/auth/realms/egi"
        # odicOrganisation: "egi"
        
        # NEW: EOEPCA Keycloak
        oidcUrl: "https://iam-auth.develop.eoepca.org/realms/eoepca"
        odicOrganisation: "eoepca"
        
        # NEW: Policy enforcement
        oidcPolicies: "openeo:user,openeo:job-executor"
        
        # JWT validation
        oidcJwksUrl: "https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/certs"
        oidcIssuer: "https://iam-auth.develop.eoepca.org/realms/eoepca"
        
        # User claim mapping
        oidcUsernameClaim: "preferred_username"
        oidcEmailClaim: "email"
        oidcGroupsClaim: "groups"
        oidcRolesClaim: "roles"
        
        # ... other configurations
```

---

## 7. CONFIGURATION DETAILS

### 7.1 Keycloak Realm Settings

```json
{
  "realm": "eoepca",
  "displayName": "EOEPCA Platform",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  
  "accessTokenLifespan": 3600,
  "accessTokenLifespanForImplicitFlow": 900,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000,
  
  "identityProviders": [
    {
      "alias": "egi-checkin",
      "providerId": "oidc",
      "enabled": true,
      "config": {
        "clientId": "eoepca-openeo",
        "authorizationUrl": "https://aai.egi.eu/auth/realms/egi/protocol/openid-connect/auth"
      }
    }
  ]
}
```

---

### 7.2 OPA Policies

Create: `argocd/eoepca/openeo-argoworkflows/parts/opa-policies.yaml`

```rego
package eoepca.openeo.api

import future.keywords.if
import future.keywords.in

# Default deny
default allow := false

# Allow if user has openeo-user role
allow if {
    "openeo-user" in input.user.roles
}

# Allow if user is in openeo-users group
allow if {
    some group in input.user.groups
    group == "/openeo/users"
}

# Job execution requires specific role
allow_job_execution if {
    "openeo-job-executor" in input.user.roles
    input.request.method == "POST"
    startswith(input.request.path, "/openeo/1.1.0/jobs")
}

# Admin endpoints require admin role
allow_admin if {
    "openeo-admin" in input.user.roles
    startswith(input.request.path, "/openeo/1.1.0/admin")
}

# Resource quotas based on group membership
user_quota := quota if {
    some group in input.user.groups
    group == "/openeo/premium"
    quota := {
        "max_concurrent_jobs": 10,
        "max_storage_gb": 100
    }
} else := {
    "max_concurrent_jobs": 2,
    "max_storage_gb": 10
}
```

---

## 8. SECURITY CONSIDERATIONS

### 8.1 Security Best Practices

✅ **Token Security:**
- Use short-lived access tokens (1 hour)
- Implement refresh token rotation
- Enable token revocation
- Validate JWT signatures using JWKS

✅ **Client Authentication:**
- Use SealedSecrets for credentials
- Rotate client secrets regularly
- Enable PKCE for public clients
- Use service accounts for backend

✅ **Network Security:**
- TLS everywhere (enforce HTTPS)
- Network policies for pod communication
- API Gateway rate limiting
- DDoS protection

✅ **Authorization:**
- Implement least privilege principle
- Use OPA for fine-grained control
- Regular policy audits
- Role-based access control (RBAC)

---

### 8.2 Secret Management

**DO:**
- ✅ Use SealedSecrets for GitOps
- ✅ Use kubernetes-secret-generator
- ✅ Rotate secrets regularly
- ✅ Encrypt secrets at rest
- ✅ Limit secret access via RBAC

**DON'T:**
- ❌ Hardcode secrets in values files
- ❌ Commit unencrypted secrets
- ❌ Share secrets across namespaces
- ❌ Use default passwords

---

### 8.3 Compliance & Auditing

- **Logging**: All authentication attempts
- **Monitoring**: Failed login tracking
- **Audit Trail**: User actions and API calls
- **GDPR**: User data protection and deletion
- **Token Introspection**: Validate active tokens

---

## 9. MIGRATION PATH

### 9.1 Migration Strategy

**Approach:** **Gradual Migration with Parallel Running**

```
┌─────────────────────────────────────────────┐
│ Phase 1: Dual Mode (EGI + Keycloak)        │
│ - Both auth methods active                  │
│ - Gradual user migration                    │
│ - Testing and validation                    │
└─────────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────┐
│ Phase 2: Keycloak Primary, EGI Federated   │
│ - Keycloak as main IdP                      │
│ - EGI Check-in as identity broker           │
│ - All new users use Keycloak                │
└─────────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────┐
│ Phase 3: Full Keycloak (Optional)          │
│ - Deprecate direct EGI integration          │
│ - EGI users login via federation            │
│ - Complete local control                    │
└─────────────────────────────────────────────┘
```

---

### 9.2 User Migration Script

```python
#!/usr/bin/env python3
"""
Migrate OpenEO users from EGI Check-in to Keycloak
"""

import requests
from keycloak import KeycloakAdmin
import psycopg2

class UserMigration:
    def __init__(self, keycloak_url, realm, admin_user, admin_pwd, db_conn):
        self.kc = KeycloakAdmin(
            server_url=keycloak_url,
            realm_name=realm,
            username=admin_user,
            password=admin_pwd
        )
        self.db = db_conn
        
    def get_existing_openeo_users(self):
        """Get users from OpenEO PostgreSQL database"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT user_id, email, username, created_at 
            FROM users 
            WHERE auth_provider = 'egi'
        """)
        return cursor.fetchall()
        
    def create_keycloak_user(self, user_data):
        """Create user in Keycloak"""
        user_payload = {
            "username": user_data['username'],
            "email": user_data['email'],
            "enabled": True,
            "emailVerified": True,
            "attributes": {
                "openeo_user_id": [user_data['user_id']],
                "migrated_from": ["egi-checkin"],
                "migration_date": [datetime.now().isoformat()]
            },
            "groups": ["/openeo/users"],
            "realmRoles": ["openeo-user"]
        }
        
        try:
            user_id = self.kc.create_user(user_payload)
            print(f"✅ Created user: {user_data['username']}")
            return user_id
        except Exception as e:
            print(f"❌ Failed to create {user_data['username']}: {e}")
            return None
            
    def link_federated_identity(self, user_id, egi_sub):
        """Link EGI Check-in identity to Keycloak user"""
        federated_identity = {
            "identityProvider": "egi-checkin",
            "userId": egi_sub,
            "userName": egi_sub
        }
        
        try:
            self.kc.add_user_federated_identity(
                user_id=user_id,
                provider_id="egi-checkin",
                federated_identity=federated_identity
            )
            print(f"✅ Linked federated identity for user {user_id}")
        except Exception as e:
            print(f"❌ Failed to link identity: {e}")
            
    def migrate_all_users(self):
        """Migrate all OpenEO users"""
        users = self.get_existing_openeo_users()
        
        for user in users:
            user_data = {
                'user_id': user[0],
                'email': user[1],
                'username': user[2],
                'created_at': user[3]
            }
            
            kc_user_id = self.create_keycloak_user(user_data)
            if kc_user_id:
                # Link to EGI if we have the sub claim
                if user_data.get('egi_sub'):
                    self.link_federated_identity(kc_user_id, user_data['egi_sub'])

# Usage
if __name__ == "__main__":
    db_conn = psycopg2.connect(
        host="openeo-postgresql",
        database="postgres",
        user="postgres",
        password=os.getenv("POSTGRES_PASSWORD")
    )
    
    migration = UserMigration(
        keycloak_url="https://iam-auth.develop.eoepca.org",
        realm="eoepca",
        admin_user="admin",
        admin_pwd=os.getenv("KC_ADMIN_PASSWORD"),
        db_conn=db_conn
    )
    
    migration.migrate_all_users()
```

---

## 10. DEPLOYMENT GUIDE

### 10.1 Prerequisites

```bash
# Check Keycloak is running
kubectl get pods -n iam -l app.kubernetes.io/name=keycloak

# Check APISIX is available
kubectl get pods -n apisix-system

# Check sealed-secrets controller
kubectl get pods -n infra -l app.kubernetes.io/name=sealed-secrets
```

---

### 10.2 Step-by-Step Deployment

#### 1. Create Keycloak Client

```bash
# Apply Crossplane client configuration
kubectl apply -f argocd/eoepca/openeo-argoworkflows/parts/keycloak-client.yaml

# Wait for client to be ready
kubectl wait --for=condition=Ready client/openeo-argoworkflows -n iam --timeout=300s

# Get client secret
kubectl get secret openeo-client-secret -n iam -o jsonpath='{.data.client-secret}' | base64 -d
```

---

#### 2. Create SealedSecret

```bash
# Generate SealedSecret with actual client secret
cd argocd/eoepca/openeo-argoworkflows

# Set environment variables
export OPENEO_CLIENT_ID="openeo-argoworkflows"
export OPENEO_CLIENT_SECRET="<from-keycloak>"

# Generate sealed secret
./ss-openeo-client.sh

# Apply sealed secret
kubectl apply -f parts/ss-openeo-api-client.yaml
```

---

#### 3. Update Helm Values

```bash
# Edit helm-openeo-argoworkflows.yaml to use Keycloak
# (See section 6.5 for configuration)

# Commit changes
git add parts/helm-openeo-argoworkflows.yaml
git commit -m "feat: migrate OpenEO to Keycloak authentication"
git push
```

---

#### 4. Apply APISIX Route

```bash
# Apply route configuration
kubectl apply -f argocd/eoepca/openeo-argoworkflows/parts/apisixroute-openeo.yaml

# Verify route is created
kubectl get apisixroute -n openeo
```

---

#### 5. Deploy Updated OpenEO

```bash
# Sync ArgoCD application
argocd app sync openeo-argoworkflows

# Watch deployment
kubectl get pods -n openeo -w

# Check logs
kubectl logs -n openeo deployment/openeo-openeo-argo -f
```

---

## 11. TESTING & VALIDATION

### 11.1 Authentication Testing

```bash
# 1. Get Keycloak token
TOKEN=$(curl -s -X POST \
  "https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=openeo-argoworkflows" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "username=${TEST_USER}" \
  -d "password=${TEST_PASSWORD}" \
  | jq -r '.access_token')

# 2. Test OpenEO endpoint
curl -H "Authorization: Bearer ${TOKEN}" \
  https://openeo-api.develop.eoepca.org/openeo/1.1.0/me

# 3. Expected response
{
  "user_id": "testuser",
  "info": {
    "email": "test@example.com",
    "groups": ["openeo-users"],
    "roles": ["openeo-user"]
  }
}
```

---

### 11.2 Integration Tests

```python
import pytest
import requests
from openeo import connect

@pytest.fixture
def openeo_connection():
    """Connect to OpenEO with Keycloak auth"""
    conn = connect("https://openeo-api.develop.eoepca.org")
    conn.authenticate_oidc(
        provider_id="eoepca",
        client_id="openeo-argoworkflows"
    )
    return conn

def test_authentication(openeo_connection):
    """Test successful authentication"""
    assert openeo_connection.describe_account() is not None

def test_list_processes(openeo_connection):
    """Test process listing"""
    processes = openeo_connection.list_processes()
    assert len(processes) > 0

def test_create_job(openeo_connection):
    """Test job creation"""
    datacube = openeo_connection.load_collection("SENTINEL2_L2A")
    job = datacube.save_result(format="GTiff").create_job()
    assert job.job_id is not None

def test_authorization_premium_user(openeo_connection_premium):
    """Test premium user can create more jobs"""
    # Premium users should be able to create up to 10 concurrent jobs
    jobs = []
    for i in range(10):
        datacube = openeo_connection_premium.load_collection("SENTINEL2_L2A")
        job = datacube.save_result(format="GTiff").create_job()
        jobs.append(job)
    
    assert len(jobs) == 10
```

---

## 12. MONITORING & MAINTENANCE

### 12.1 Monitoring Dashboards

```yaml
# Prometheus metrics to monitor
- keycloak_login_attempts_total
- keycloak_login_failures_total
- keycloak_active_sessions
- openeo_authentication_requests_total
- openeo_authorization_decisions_total
- apisix_http_status{route="openeo-api"}
```

---

### 12.2 Log Aggregation

```bash
# Keycloak logs
kubectl logs -n iam deployment/iam-keycloak -f | grep openeo

# APISIX logs
kubectl logs -n apisix-system deployment/apisix -f | grep openeo

# OpenEO API logs
kubectl logs -n openeo deployment/openeo-openeo-argo -f | grep -i auth
```

---

### 12.3 Alerts

```yaml
# Prometheus alert rules
groups:
  - name: openeo-auth
    rules:
      - alert: HighAuthenticationFailureRate
        expr: |
          rate(keycloak_login_failures_total{client="openeo-argoworkflows"}[5m]) > 0.1
        for: 5m
        annotations:
          summary: "High authentication failure rate for OpenEO"
          
      - alert: KeycloakDown
        expr: up{job="keycloak"} == 0
        for: 1m
        annotations:
          summary: "Keycloak is down - OpenEO authentication unavailable"
```

---

## 13. ROLLBACK STRATEGY

### 13.1 Rollback Plan

If issues occur, revert to EGI Check-in:

```bash
# 1. Update Helm values back to EGI
git revert <commit-hash>
git push

# 2. Sync ArgoCD
argocd app sync openeo-argoworkflows

# 3. Remove APISIX route
kubectl delete apisixroute openeo-api -n openeo

# 4. Verify service
curl https://openeo-api.develop.eoepca.org/openeo/1.1.0/
```

---

### 13.2 Rollback Triggers

Rollback if:
- ❌ Authentication success rate < 95%
- ❌ API latency increases > 50%
- ❌ Critical bugs in production
- ❌ Data loss or corruption
- ❌ Keycloak unavailability > 5 minutes

---

## 14. FUTURE ENHANCEMENTS

### 14.1 Advanced Features

1. **Multi-Factor Authentication (MFA)**
   - TOTP support
   - WebAuthn/FIDO2
   - SMS-based OTP

2. **Advanced Authorization**
   - Resource-based policies
   - Dynamic permissions
   - Temporary access grants

3. **Federation**
   - eduGAIN integration
   - Additional IdPs (Google, GitHub)
   - SAML support

4. **User Management**
   - Self-service password reset
   - Profile management
   - API key generation

5. **Monitoring**
   - User behavior analytics
   - Security incident detection
   - Compliance reporting

---

## 15. APPENDICES

### Appendix A: Glossary

- **OIDC**: OpenID Connect - Authentication protocol
- **OAuth2**: Authorization framework
- **JWT**: JSON Web Token
- **UMA2**: User-Managed Access 2.0
- **JWKS**: JSON Web Key Set
- **OPA**: Open Policy Agent
- **APISIX**: API Gateway
- **SealedSecret**: Encrypted Kubernetes secret

---

### Appendix B: Useful Commands

```bash
# Get Keycloak admin password
kubectl get secret iam-keycloak -n iam -o jsonpath='{.data.admin-password}' | base64 -d

# Access Keycloak admin console
kubectl port-forward -n iam svc/iam-keycloak 8080:80
# Open: http://localhost:8080

# Test OIDC discovery
curl https://iam-auth.develop.eoepca.org/realms/eoepca/.well-known/openid-configuration | jq

# Decode JWT token
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq

# Test APISIX route
curl -v https://openeo-api.develop.eoepca.org/openeo/1.1.0/
```

---

### Appendix C: References

- **Keycloak Documentation**: https://www.keycloak.org/documentation
- **EOEPCA IAM BB**: https://eoepca.github.io/
- **OpenEO API**: https://openeo.org/documentation/
- **EGI Check-in**: https://docs.egi.eu/users/aai/check-in/
- **APISIX Plugins**: https://apisix.apache.org/docs/apisix/plugins/
- **OPA Documentation**: https://www.openpolicyagent.org/docs/

---

### Appendix D: Contact & Support

- **EOEPCA Team**: https://eoepca.org
- **OpenEO Community**: https://openeo.org
- **Keycloak Community**: https://www.keycloak.org/community

---

## CONCLUSION

This comprehensive strategy provides a complete roadmap for migrating OpenEO-ArgoWorkflows from direct EGI Check-in integration to a **Keycloak-based architecture** with EGI federation. The approach:

✅ **Maintains EGI compatibility** through identity brokering
✅ **Provides local control** over authentication and authorization
✅ **Integrates with EOEPCA** IAM infrastructure
✅ **Enables fine-grained policies** via OPA
✅ **Follows security best practices**
✅ **Supports gradual migration** with minimal disruption

**Recommended Next Steps:**
1. Review and approve this strategy
2. Set up development environment
3. Begin Phase 1 implementation
4. Test with pilot users
5. Gradual rollout to production

---

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Status:** ✅ Ready for Implementation
