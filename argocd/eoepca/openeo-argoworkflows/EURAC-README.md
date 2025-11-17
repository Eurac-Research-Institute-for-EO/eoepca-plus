# EURAC Authentication for OpenEO

This directory contains the configuration for integrating EURAC Research SAML authentication with OpenEO via Keycloak.

## 📚 Documentation

- **[EURAC Authentication Setup Guide](../../../docs/eurac-authentication-setup.md)** - Complete implementation guide
- **[Keycloak Integration Strategy](../../../docs/keycloak-integration-strategy.md)** - Overall architecture and strategy

## 🗂️ Files

### Configuration Files

- `parts/keycloak-idp-eurac.yaml` - EURAC SAML Identity Provider definition
- `parts/keycloak-eurac-mappers.yaml` - SAML attribute mappers (email, name, affiliation, etc.)
- `parts/keycloak-eurac-group.yaml` - EURAC researchers group definition

### Deployment

- `deploy-eurac-auth.sh` - Automated deployment script

## 🚀 Quick Start

### Prerequisites

1. Keycloak (IAM Building Block) is running
2. `eoepca` realm exists
3. Crossplane Keycloak provider is configured
4. kubectl access to the cluster

### Deploy EURAC Authentication

```bash
# Navigate to this directory
cd argocd/eoepca/openeo-argoworkflows

# Run deployment script
./deploy-eurac-auth.sh
```

### Manual Deployment

```bash
# Apply EURAC Identity Provider
kubectl apply -f parts/keycloak-idp-eurac.yaml

# Apply attribute mappers
kubectl apply -f parts/keycloak-eurac-mappers.yaml

# Create EURAC group
kubectl apply -f parts/keycloak-eurac-group.yaml

# Verify deployment
kubectl get identityprovider -n iam eurac-research-saml
kubectl get identityprovidermapper -n iam | grep eurac
kubectl get group -n iam eurac-researchers
```

## 🔐 EURAC SSO Details

- **Entity ID**: https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php
- **SSO URL**: https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php
- **Metadata**: https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php
- **Protocol**: SAML 2.0 via eduGAIN

## 🧪 Testing

### Test Login Flow

```bash
# Get EURAC login URL
EURAC_LOGIN_URL="https://iam-auth.develop.eoepca.org/realms/eoepca/protocol/openid-connect/auth?client_id=openeo-argoworkflows&redirect_uri=https://openeo-api.develop.eoepca.org/callback&response_type=code&scope=openid%20profile%20email&kc_idp_hint=eurac-research"

echo "Test EURAC Login:"
echo "$EURAC_LOGIN_URL"
```

### Verify User Creation

After successful login:

```bash
# Check Keycloak logs
kubectl logs -n iam deployment/iam-keycloak -f | grep eurac

# List EURAC users
kubectl exec -n iam deployment/iam-keycloak -- \
  /opt/keycloak/bin/kcadm.sh get users -r eoepca \
  | jq '.[] | select(.federatedIdentities[].identityProvider == "eurac-research")'
```

## 📋 Service Provider Registration

To register OpenEO with EURAC IT:

**Contact**: it-support@eurac.edu

**Information to provide**:
- Service Name: OpenEO EOEPCA Platform
- Entity ID: `https://iam-auth.develop.eoepca.org/realms/eoepca`
- ACS URL: `https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint`
- Metadata URL: `https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor`

**Requested Attributes**:
- `mail` (email address)
- `givenName` (first name)
- `sn` (last name)
- `displayName`
- `eduPersonPrincipalName`
- `eduPersonScopedAffiliation`

## 🔍 Troubleshooting

### Check Identity Provider Status

```bash
kubectl get identityprovider eurac-research-saml -n iam -o yaml
```

### View SAML Metadata

```bash
curl -s https://iam-auth.develop.eoepca.org/realms/eoepca/broker/eurac-research/endpoint/descriptor \
  | xmllint --format -
```

### Monitor Authentication Events

```bash
# Keycloak logs
kubectl logs -n iam deployment/iam-keycloak -f | grep -i "eurac\|saml"

# Check events in Keycloak Admin UI
# Navigate to: Realm Settings → Events → Login events
```

### Common Issues

1. **Signature Validation Failed**
   - Verify EURAC metadata is loaded correctly
   - Check `validateSignature: true` in IdP config

2. **Missing Attributes**
   - Verify EURAC releases required attributes
   - Check attribute OID mappings in mappers

3. **User Not Created**
   - Check first broker login flow is configured
   - Verify email is received from EURAC

## 📊 User Quotas

EURAC researchers automatically get:
- **Concurrent Jobs**: 10
- **Storage**: 100 GB
- **Priority**: High
- **Group**: `/organizations/eurac`

## 🔗 Related Components

- **IAM Building Block**: `argocd/eoepca/iam/`
- **OpenEO API**: `argocd/eoepca/openeo-argoworkflows/`
- **APISIX Gateway**: `argocd/infra/apisix/`

## 📞 Support

- **EURAC IT Support**: it-support@eurac.edu
- **EOEPCA Team**: https://eoepca.org
- **Documentation**: https://eoepca.github.io/

---

**Last Updated**: November 10, 2025  
**Status**: ✅ Ready for Deployment
