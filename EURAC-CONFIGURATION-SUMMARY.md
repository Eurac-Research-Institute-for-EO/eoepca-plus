# 🎯 EURAC Authentication Configuration - Summary

## What Was Created

Complete EURAC Research SAML authentication integration for OpenEO-ArgoWorkflows via Keycloak.

---

## 📁 Files Created

### 1. Documentation

#### `/docs/eurac-authentication-setup.md` (Complete Implementation Guide)
- **10 sections** covering EURAC SAML integration
- Architecture diagrams and authentication flows
- Step-by-step Keycloak configuration
- Crossplane resource definitions
- Testing procedures
- Troubleshooting guide
- Production deployment checklist

#### `/docs/keycloak-integration-strategy.md` (Updated)
- Architecture updated to include EURAC as primary IdP
- Federation diagram includes EURAC SSO
- References EURAC alongside EGI Check-in

---

### 2. Kubernetes Resources (Crossplane CRDs)

#### `argocd/eoepca/openeo-argoworkflows/parts/keycloak-idp-eurac.yaml`
**EURAC SAML Identity Provider**
```yaml
- Entity: IdentityProvider (Crossplane)
- Name: eurac-research-saml
- Provider: SAML 2.0
- SSO URL: https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php
- Metadata: Auto-fetch from EURAC
- Features:
  ✅ Signature validation
  ✅ SAML attribute import
  ✅ First broker login flow
  ✅ Email trust enabled
```

#### `argocd/eoepca/openeo-argoworkflows/parts/keycloak-eurac-mappers.yaml`
**SAML Attribute Mappers (7 mappers)**
```yaml
Mappers:
1. email → user.email (urn:oid:0.9.2342.19200300.100.1.3)
2. firstName → user.firstName (urn:oid:2.5.4.42)
3. lastName → user.lastName (urn:oid:2.5.4.4)
4. displayName → user.displayName (urn:oid:2.16.840.1.113730.3.1.241)
5. affiliation → user.affiliation (urn:oid:1.3.6.1.4.1.5923.1.1.1.9)
6. eppn → user.eppn (urn:oid:1.3.6.1.4.1.5923.1.1.1.6)
7. username → ${NAMEID}@eurac (username template)
```

#### `argocd/eoepca/openeo-argoworkflows/parts/keycloak-eurac-group.yaml`
**EURAC Researchers Group**
```yaml
- Group: /organizations/eurac
- Attributes:
  - max_concurrent_jobs: 10
  - max_storage_gb: 100
  - priority: high
  - organization: eurac
  - organization_name: EURAC Research
```

---

### 3. Automation & Scripts

#### `argocd/eoepca/openeo-argoworkflows/deploy-eurac-auth.sh`
**Automated Deployment Script**
```bash
Features:
✅ Prerequisite checks (Keycloak, realm)
✅ Apply IdP configuration
✅ Deploy attribute mappers
✅ Create EURAC group
✅ Generate SP metadata for EURAC registration
✅ Provide test instructions
```

#### `argocd/eoepca/openeo-argoworkflows/EURAC-README.md`
**Quick Reference Guide**
- Quick start instructions
- EURAC SSO details
- Testing commands
- Troubleshooting tips
- SP registration information

---

## 🏗️ Architecture

### Authentication Flow

```
EURAC User (researcher@eurac.edu)
    ↓
    ↓ 1. Access OpenEO
    ↓
OpenEO Web UI
    ↓
    ↓ 2. "Login with EURAC"
    ↓
EOEPCA Keycloak (Realm: eoepca)
    ↓
    ↓ 3. SAML AuthnRequest
    ↓
EURAC SSO (sso.eurac.edu)
    ↓
    ↓ 4. User authenticates
    ↓ 5. SAML Response + attributes
    ↓
EOEPCA Keycloak
    ↓ Maps attributes
    ↓ Creates/updates user
    ↓ Assigns to /organizations/eurac group
    ↓
    ↓ 6. OIDC JWT Token
    ↓
APISIX Gateway
    ↓ Validates JWT
    ↓ Enforces policies
    ↓
    ↓ 7. Authorized request
    ↓
OpenEO API
    ↓ Process graphs
    ↓ Job execution
```

---

## 🚀 Deployment Steps

### Prerequisites
- ✅ Keycloak (IAM BB) deployed
- ✅ Realm `eoepca` exists
- ✅ Crossplane Keycloak provider configured
- ✅ kubectl access

### Automated Deployment
```bash
cd argocd/eoepca/openeo-argoworkflows
./deploy-eurac-auth.sh
```

### Manual Deployment
```bash
# 1. Apply EURAC Identity Provider
kubectl apply -f parts/keycloak-idp-eurac.yaml

# 2. Apply attribute mappers
kubectl apply -f parts/keycloak-eurac-mappers.yaml

# 3. Create EURAC group
kubectl apply -f parts/keycloak-eurac-group.yaml

# 4. Verify
kubectl get identityprovider -n iam eurac-research-saml
kubectl get identityprovidermapper -n iam | grep eurac
kubectl get group -n iam eurac-researchers
```

---

## 🧪 Testing

### Test EURAC Login
```bash
# Construct login URL with EURAC hint
https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/auth?client_id=openeo-argoworkflows&redirect_uri=https://openeo-api.develop.eoepca.org/callback&response_type=code&scope=openid%20profile%20email&kc_idp_hint=eurac-research
```

### Verify User Creation
```bash
# Check Keycloak logs
kubectl logs -n iam deployment/iam-keycloak -f | grep eurac

# List EURAC users
kubectl get users -n iam
```

### Validate JWT Token
```bash
# After authentication, decode token
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq

# Expected claims:
{
  "sub": "...",
  "email": "researcher@eurac.edu",
  "preferred_username": "researcher@eurac",
  "affiliation": "staff@eurac.edu",
  "eppn": "researcher@eurac.edu",
  "groups": ["/organizations/eurac", "/openeo/users"]
}
```

---

## 📋 EURAC Service Provider Registration

### Information for EURAC IT

**Contact**: it-support@eurac.edu

**Service Details**:
- **Service Name**: OpenEO EOEPCA Platform
- **Purpose**: Earth Observation data processing for EURAC researchers
- **Entity ID**: `https://iam-auth.develop.eoepca.org/realms/eoepca`
- **ACS URL**: `https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint`
- **Metadata URL**: `https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor`

**Requested Attributes** (via eduGAIN):
- ✅ `mail` - Email address
- ✅ `givenName` - First name
- ✅ `sn` - Last name
- ✅ `displayName` - Full name
- ✅ `eduPersonPrincipalName` - Unique identifier
- ✅ `eduPersonScopedAffiliation` - Role/status

---

## 🎁 Features & Benefits

### For EURAC Researchers
- ✅ **Single Sign-On**: Use existing EURAC credentials
- ✅ **No Registration**: Automatic account creation
- ✅ **Enhanced Quota**: 10 concurrent jobs, 100GB storage
- ✅ **Priority Processing**: High-priority queue
- ✅ **Institutional Access**: Part of /organizations/eurac group

### For Administrators
- ✅ **Declarative Config**: GitOps with Crossplane
- ✅ **Automated Deployment**: One-command setup
- ✅ **SAML Federation**: Standard eduGAIN integration
- ✅ **Attribute Mapping**: Automatic user profile sync
- ✅ **Group Management**: Auto-assignment to EURAC group

### For Platform
- ✅ **Keycloak Integration**: Centralized IAM
- ✅ **OIDC Tokens**: Standard JWT for APIs
- ✅ **Policy Enforcement**: OPA-ready authorization
- ✅ **Audit Trail**: Full authentication logging

---

## 🔐 Security Features

- ✅ **SAML Signature Validation**: Ensures authentic responses
- ✅ **TLS Everywhere**: Encrypted communication
- ✅ **Trusted Email**: Email verified by EURAC
- ✅ **Attribute Filtering**: Only required attributes imported
- ✅ **JWT Security**: Short-lived tokens with validation
- ✅ **Group-based Authorization**: Fine-grained access control

---

## 📊 User Quotas (EURAC Researchers)

| Resource | Quota | Notes |
|----------|-------|-------|
| Concurrent Jobs | 10 | vs 2 for regular users |
| Storage | 100 GB | vs 10 GB for regular users |
| Priority | High | Faster job scheduling |
| Group | /organizations/eurac | Institutional affiliation |

---

## 🔍 Monitoring & Troubleshooting

### Logs
```bash
# Keycloak authentication logs
kubectl logs -n iam deployment/iam-keycloak -f | grep eurac

# APISIX gateway logs
kubectl logs -n apisix-system deployment/apisix -f

# OpenEO API logs
kubectl logs -n openeo deployment/openeo-openeo-argo -f
```

### Common Issues

**1. Signature Validation Failed**
- Check EURAC metadata is loaded
- Verify certificate in metadata is valid

**2. Missing Attributes**
- Confirm EURAC releases attributes to SP
- Check attribute OID mappings

**3. User Not Created**
- Verify first broker login flow
- Check email attribute is received

---

## 📚 Additional Resources

- **EURAC SSO**: https://sso.eurac.edu/
- **EURAC IT Support**: it-support@eurac.edu
- **eduGAIN**: https://edugain.org/
- **Keycloak Docs**: https://www.keycloak.org/docs/
- **EOEPCA IAM**: https://eoepca.github.io/

---

## ✅ Next Steps

1. **Review Configuration**
   - Verify all files are correct
   - Check EURAC SSO endpoints are accessible

2. **Deploy to Development**
   ```bash
   cd argocd/eoepca/openeo-argoworkflows
   ./deploy-eurac-auth.sh
   ```

3. **Test with EURAC Account**
   - Use test credentials from EURAC
   - Verify login flow works
   - Check user attributes are correct

4. **Register with EURAC IT**
   - Send SP metadata to EURAC
   - Request attribute release
   - Confirm registration

5. **Production Deployment**
   - Update kustomization.yaml
   - Commit to git
   - Sync via ArgoCD

6. **User Communication**
   - Notify EURAC researchers
   - Provide login instructions
   - Share documentation link

---

## 📝 Summary

**Created**: Complete EURAC SAML authentication for OpenEO

**Components**:
- ✅ SAML Identity Provider (EURAC SSO)
- ✅ 7 Attribute Mappers (email, name, affiliation, etc.)
- ✅ EURAC Researchers Group (enhanced quotas)
- ✅ Deployment automation script
- ✅ Comprehensive documentation (2 guides)
- ✅ Quick reference README

**Status**: ✅ **Ready for Deployment**

**Integration Method**: Keycloak SAML Identity Brokering via eduGAIN

**Authentication Flow**: EURAC SSO (SAML) → Keycloak (OIDC) → OpenEO API

---

**Document Created**: November 10, 2025  
**Branch**: egi-checkin-investigation  
**Ready for**: Development testing and EURAC registration
