# 🚀 Quick Test Reference Card

## Essential URLs (Port-Forward Mode)

| Service | URL | Credentials |
|---------|-----|-------------|
| **Keycloak Admin** | http://localhost:8443/admin/master/console/ | admin / changeme123 |
| **EURAC Login** | http://localhost:8443/realms/eoepca/broker/eurac-research/login | EURAC credentials |
| **OpenEO Docs** | http://localhost:8000/docs | - |
| **OIDC Discovery** | http://localhost:8443/realms/eoepca/.well-known/openid-configuration | - |

## Quick Commands

### Start Port Forwards
```bash
kubectl port-forward -n iam pod/iam-keycloak-0 8443:8080 &
kubectl port-forward -n openeo svc/openeo-openeo-argo 8000:8000 &
```

### Run Automated Tests
```bash
./test-eurac-authentication.sh
```

### Check Port Forwards
```bash
ps aux | grep port-forward | grep -v grep
```

### Get Admin Token
```bash
curl -s -X POST "http://localhost:8443/realms/eoepca/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=changeme123" \
  -d "grant_type=password" | jq -r '.access_token'
```

### Check EURAC IdP Status
```bash
TOKEN="<admin-token>"
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8443/admin/realms/eoepca/identity-provider/instances/eurac-research" | jq
```

### Check OpenEO OIDC Client
```bash
TOKEN="<admin-token>"
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8443/admin/realms/eoepca/clients" | \
  jq '.[] | select(.clientId == "openeo")'
```

## What to Test

- [ ] Open Keycloak admin console → verify eoepca realm exists
- [ ] Check Identity Providers → EURAC Research should be enabled
- [ ] Check Clients → openeo client should be enabled
- [ ] Click EURAC login URL → should redirect to sso.eurac.edu
- [ ] Open OpenEO docs → should show API documentation
- [ ] Run test script → all checks should pass ✅

## Expected Login Flow

```
Browser → Keycloak EURAC Login URL
    ↓
Redirect to sso.eurac.edu
    ↓
User enters EURAC credentials
    ↓
EURAC SSO validates credentials
    ↓
Redirect back to Keycloak with SAML assertion
    ↓
Keycloak creates/updates user
    ↓
User logged in with attributes mapped
```

## Configuration Values

```
Realm:              eoepca
EURAC IdP:          eurac-research
EURAC SSO:          https://sso.eurac.edu/auth/realms/eurac/protocol/saml
OpenEO Client ID:   openeo
Client Secret:      ZPYkOdkJOZl2v0yuHsOxxxGNMtQ6V9Ke
```

## Troubleshooting

**Can't access Keycloak?**
```bash
kubectl get pods -n iam | grep keycloak
kubectl logs -n iam iam-keycloak-0 --tail=20
```

**Can't access OpenEO?**
```bash
kubectl get pods -n openeo
kubectl logs -n openeo deployment/openeo-openeo-argo -c openeo-argo --tail=20
```

**Port forward died?**
```bash
pkill -f "port-forward.*8443"
pkill -f "port-forward.*8000"
# Then restart them
```

## Files to Read

- `TESTING-GUIDE.md` - Detailed testing instructions
- `test-eurac-authentication.sh` - Automated test script
- `docs/EURAC-AUTH-EXPLAINED-SIMPLE.md` - Simple explanation
- `EURAC-CONFIGURATION-SUMMARY.md` - Full config details
