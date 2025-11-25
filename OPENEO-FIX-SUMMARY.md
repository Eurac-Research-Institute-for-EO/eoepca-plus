# OpenEO EURAC Keycloak Authentication Fix - Summary

## Problem Statement
Users attempting to login to `https://openeo-eurac.develop.eoepca.org` with Scientificnet-OpenEO authentication were receiving a **500 Internal Server Error** during the OAuth callback.

## Root Cause
The APISIX openid-connect plugin configuration was missing the required `scope` parameter. When APISIX attempted to exchange the authorization code for an access token, Keycloak rejected the request because no scope was specified.

## Solution Implemented

### 1. Configuration Changes (PR #5)
**Pull Request**: https://github.com/Eurac-Research-Institute-for-EO/eoepca-plus/pull/5
**Status**: ✅ Merged to `deploy-develop` branch on 2025-11-24 at 13:34:16

**File Modified**: `argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml`

**Key Changes**:
- ✅ **Added `scope: "openid email profile"`** - Critical fix for OIDC token exchange
- ✅ Added `session_secret` for secure session cookie encryption
- ✅ Added `unauth_action: "auth"` to redirect unauthenticated users
- ✅ Increased `timeout` from 10 to 30 seconds
- ✅ Added `ssl_verify: false` for internal certificate handling
- ✅ Added token expiry and refresh parameters
- ✅ Updated `client_secret` to match current Keycloak configuration

### 2. Deployment Status

**Development Environment (Minikube)**:
- Location: `192.168.58.2`
- Status: ✅ Manually updated with fix
- Note: This is NOT where `openeo-eurac.develop.eoepca.org` points to

**Production Environment** (where fix needs to be deployed):
- Location: `64.225.140.153` (develop.eoepca.org)
- Status: ⏳ Waiting for ArgoCD workflow to sync changes
- Action: Team member has been asked to trigger ArgoCD sync

## Architecture Overview

```
User Browser
    ↓
https://openeo-eurac.develop.eoepca.org (64.225.140.153)
    ↓
[Production RKE Cluster]
    ├── APISIX Gateway (handles OIDC authentication)
    │   └── openid-connect plugin with EURAC Keycloak
    └── OpenEO Backend (openeo-openeo-argo)
        └── Configured for EURAC Keycloak: edp-portal.eurac.edu
```

## Expected Results After Deployment

### Test 1: Browser Login Flow
1. Navigate to: `https://openeo-eurac.develop.eoepca.org/openeo/1.1.0/jobs`
2. Should redirect to EURAC Keycloak login page
3. Click "Scientificnet-OpenEO"
4. Complete authentication
5. **Expected**: Successfully redirect back to OpenEO (no 500 error)
6. **Expected**: See JSON response like `{"jobs":[],"links":[]}`

### Test 2: Python Client Authentication
```python
import openeo

# Connect to OpenEO backend
connection = openeo.connect("https://openeo-eurac.develop.eoepca.org/openeo/1.1.0")

# Should now show EURAC provider instead of EGI
print(connection.list_oidc_providers())

# Authenticate (will open browser)
connection.authenticate_oidc()

# Verify authentication worked
print(connection.describe_account())
```

### Test 3: Check OIDC Provider Configuration
```bash
curl -s https://openeo-eurac.develop.eoepca.org/openeo/1.1.0/credentials/oidc | jq .
```

**Expected output should include**:
```json
{
  "providers": [
    {
      "id": "eurac",
      "issuer": "https://edp-portal.eurac.edu/auth/realms/edp",
      "title": "EURAC Keycloak",
      ...
    }
  ]
}
```

(Not EGI Check-in)

## Troubleshooting

### If 500 Error Persists After Deployment

1. **Verify ArgoCD sync completed**:
   - Check that the deployment was updated
   - Check pod restart time matches recent deployment

2. **Check APISIX route configuration** (on production cluster):
   ```bash
   kubectl get apisixroute -n openeo openeo-route -o jsonpath='{.spec.http[1].plugins[0].config.scope}'
   ```
   Should return: `openid email profile`

3. **Check OpenEO backend configuration**:
   ```bash
   kubectl get deployment -n openeo openeo-openeo-argo -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name | contains("OIDC"))'
   ```
   Should show:
   - `OIDC_URL`: `https://edp-portal.eurac.edu/auth/realms/edp`
   - `OIDC_CLIENT_ID`: `openEO`
   - `OIDC_CLIENT_SECRET`: `8f7f2fb0-4347-44be-b5be-d752cbd3de11`

4. **Check APISIX logs** (if needed):
   ```bash
   kubectl logs -n iam <apisix-pod-name> --tail=100
   ```

### If Web Editor Shows Version Error

The OpenEO Web Editor (https://editor.openeo.org) has strict version checking. This is a separate issue from authentication.

**Workaround**: Use the Python client instead:
```python
import openeo
connection = openeo.connect("https://openeo-eurac.develop.eoepca.org/openeo/1.1.0")
```

## Configuration Details

### EURAC Keycloak Configuration
- **URL**: `https://edp-portal.eurac.edu/auth`
- **Realm**: `edp`
- **Client ID**: `openEO`
- **Client Secret**: `8f7f2fb0-4347-44be-b5be-d752cbd3de11`
- **Valid Redirect URIs**:
  - `https://openeo-eurac.develop.eoepca.org/*`
  - `https://openeo-eurac.develop.eoepca.org/apisix/redirect`
  - `https://editor.openeo.org/*`
  - `http://localhost:1410/*`

### Authentication Flow
1. User accesses protected endpoint
2. APISIX intercepts and redirects to Keycloak
3. User authenticates via Scientificnet-OpenEO
4. Keycloak redirects to: `https://openeo-eurac.develop.eoepca.org/apisix/redirect?code=XXX&state=YYY`
5. APISIX exchanges authorization code for access token (with `scope` parameter)
6. APISIX creates session cookie
7. User is redirected to original endpoint with valid session

## Timeline

- **2025-11-24 13:34**: PR #5 merged to `deploy-develop`
- **2025-11-24 14:xx**: ArgoCD workflow triggered to deploy changes
- **Next**: Verify deployment and test authentication

## Security Note

The client secrets and session secrets in the configuration files are stored in plain text in Git. For improved security, consider:

1. Using Sealed Secrets (already available in the repo)
2. Moving secrets to External Secrets Operator (ESO)
3. Rotating secrets after implementing proper secret management

## References

- **PR**: https://github.com/Eurac-Research-Institute-for-EO/eoepca-plus/pull/5
- **APISIX Plugin Docs**: https://apisix.apache.org/docs/apisix/plugins/openid-connect/
- **Keycloak OIDC Discovery**: https://edp-portal.eurac.edu/auth/realms/edp/.well-known/openid-configuration
- **OpenEO API**: https://openeo-eurac.develop.eoepca.org/openeo/1.1.0/

## Next Steps

1. ⏳ **Wait for ArgoCD deployment to complete**
2. ✅ **Test authentication flow** (as described above)
3. ✅ **Verify no 500 errors**
4. ✅ **Test Python client integration**
5. 📋 **Document successful login** for team
6. 🔒 **Consider implementing Sealed Secrets** (follow-up task)

## Contact

For issues or questions:
- Check ArgoCD dashboard for deployment status
- Review cluster logs if errors persist
- Verify Keycloak client configuration at: https://edp-portal.eurac.edu/auth/admin
