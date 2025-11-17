# EURAC Authentication Testing Guide

## 🎯 Quick Start

All components are deployed and configured! Use the test script or follow the manual steps below.

### Automated Testing

```bash
./test-eurac-authentication.sh
```

This script validates:
- ✅ Port forwards are running
- ✅ Keycloak is accessible
- ✅ EURAC Identity Provider is configured
- ✅ OpenEO OIDC client is enabled
- ✅ OpenEO API is responsive

---

## �� Manual Testing Steps

### 1. Ensure Port Forwards are Running

You need two port-forwards active:

**Terminal 1 - Keycloak:**
```bash
kubectl port-forward -n iam pod/iam-keycloak-0 8443:8080
```

**Terminal 2 - OpenEO:**
```bash
kubectl port-forward -n openeo svc/openeo-openeo-argo 8000:8000
```

Check if running:
```bash
ps aux | grep port-forward | grep -v grep
```

---

### 2. Test Keycloak Admin Access

**URL:** http://localhost:8443/admin/master/console/

**Credentials:**
- Username: `admin`
- Password: `changeme123`

**What to verify:**
- Navigate to "eoepca" realm (top-left dropdown)
- Go to "Identity providers" → should see "EURAC Research"
- Go to "Clients" → should see "openeo" client

---

### 3. Test EURAC SAML Login Flow

**Direct EURAC Login URL:**
```
http://localhost:8443/realms/eoepca/broker/eurac-research/login
```

**Expected Flow:**
1. Browser redirects to `https://sso.eurac.edu`
2. You see EURAC institutional login page
3. After login with EURAC credentials:
   - Redirected back to Keycloak
   - User profile created automatically
   - SAML attributes mapped (email, name, affiliation, etc.)

**Note:** You need valid EURAC credentials to complete this flow.

---

### 4. View User Created from EURAC Login

After logging in via EURAC:

1. Go to Keycloak Admin Console
2. Navigate to "Users" in eoepca realm
3. You should see the user created from EURAC SAML
4. Click on the user to see:
   - Email (from SAML)
   - First Name (from SAML)
   - Last Name (from SAML)
   - Username (from eduPersonPrincipalName)
   - Attributes: affiliation, eppn, etc.

---

### 5. Test OpenEO API

**OpenEO API Documentation:**
```
http://localhost:8000/docs
```

This shows the FastAPI/Swagger UI with all available endpoints.

**Test Basic Endpoint:**
```bash
curl http://localhost:8000/docs
```

---

### 6. Test OIDC Token Flow

**Get Admin Token (for testing):**
```bash
curl -X POST "http://localhost:8443/realms/eoepca/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=changeme123" \
  -d "grant_type=password"
```

**Get Token for EURAC User:**
After a user logs in via EURAC SAML, they can get tokens:

```bash
curl -X POST "http://localhost:8443/realms/eoepca/protocol/openid-connect/token" \
  -d "client_id=openeo" \
  -d "client_secret=ZPYkOdkJOZl2v0yuHsOxxxGNMtQ6V9Ke" \
  -d "grant_type=password" \
  -d "username=<eurac-username>" \
  -d "password=<eurac-password>"
```

Replace `<eurac-username>` with the username created from EURAC login.

**Use Token with OpenEO:**
```bash
TOKEN="<your-access-token>"
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/endpoint
```

---

## 📊 Verification Checklist

Use this checklist to verify everything is working:

- [ ] Port forwards running (Keycloak on 8443, OpenEO on 8000)
- [ ] Can access Keycloak admin console
- [ ] EURAC Identity Provider visible in eoepca realm
- [ ] EURAC IdP shows as "enabled"
- [ ] 7 attribute mappers configured
- [ ] OpenEO OIDC client exists and is enabled
- [ ] Can access http://localhost:8000/docs
- [ ] EURAC login redirects to sso.eurac.edu
- [ ] User created after EURAC login with SAML attributes
- [ ] Can obtain OIDC token from Keycloak

---

## 🔍 Troubleshooting

### Port Forward Fails
```bash
# Kill existing port forwards
pkill -f "port-forward.*iam.*8443"
pkill -f "port-forward.*openeo.*8000"

# Restart them
kubectl port-forward -n iam pod/iam-keycloak-0 8443:8080 &
kubectl port-forward -n openeo svc/openeo-openeo-argo 8000:8000 &
```

### Keycloak Not Accessible
```bash
# Check Keycloak pod
kubectl get pods -n iam | grep keycloak

# Check logs
kubectl logs -n iam iam-keycloak-0 --tail=50
```

### OpenEO Not Responding
```bash
# Check OpenEO pods
kubectl get pods -n openeo

# Check OpenEO logs
kubectl logs -n openeo deployment/openeo-openeo-argo -c openeo-argo --tail=50
```

### EURAC Login Fails
- Verify EURAC IdP is enabled in Keycloak admin
- Check EURAC SSO endpoint: https://sso.eurac.edu
- Verify SAML metadata is correctly configured
- Check Keycloak logs for SAML errors

---

## 📋 Configuration Summary

| Component | Value |
|-----------|-------|
| Keycloak URL (internal) | http://iam-keycloak.iam.svc.cluster.local |
| Keycloak URL (port-forward) | http://localhost:8443 |
| Keycloak Realm | eoepca |
| EURAC IdP Alias | eurac-research |
| EURAC SSO URL | https://sso.eurac.edu/auth/realms/eurac/protocol/saml |
| OpenEO OIDC Client ID | openeo |
| OpenEO Client Secret | ZPYkOdkJOZl2v0yuHsOxxxGNMtQ6V9Ke |
| OpenEO URL (port-forward) | http://localhost:8000 |

---

## 🎉 Success Indicators

When everything is working correctly, you should see:

1. **Keycloak Admin Console** shows:
   - "EURAC Research" identity provider (enabled)
   - "openeo" OIDC client (enabled)
   - Users created from EURAC login

2. **EURAC Login Flow**:
   - Redirects to sso.eurac.edu
   - After login, redirects back
   - User automatically created in Keycloak
   - SAML attributes populated

3. **OpenEO Integration**:
   - API accessible at localhost:8000
   - API documentation available at /docs
   - Accepts Bearer tokens from Keycloak
   - OIDC configuration environment variables set

---

## 📚 Related Documentation

- Full Setup Guide: `docs/eurac-authentication-setup.md`
- Integration Strategy: `docs/keycloak-integration-strategy.md`
- Simple Explanation: `docs/EURAC-AUTH-EXPLAINED-SIMPLE.md`
- Stakeholder Demo: `docs/EURAC-STAKEHOLDER-DEMO.md`
- Configuration Summary: `EURAC-CONFIGURATION-SUMMARY.md`

---

## 🚀 Next Steps for Production

Current setup works via port-forwards for testing. For production:

1. Configure proper DNS records
2. Set up ingress/gateway with TLS
3. Update Keycloak admin password
4. Rotate client secrets
5. Configure session timeouts
6. Enable audit logging
7. Set up monitoring and alerts

See `EURAC-CONFIGURATION-SUMMARY.md` for the complete production checklist.
