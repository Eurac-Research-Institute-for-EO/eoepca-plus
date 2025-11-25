# OpenEO 500 Error Fix - Host Header Issue

## Problem
When accessing `openeo-eurac.develop.eoepca.org` and logging in with Scientificnet-OpenEO, the authentication callback was failing with a 500 error.

**Root Cause:** The APISIX openid-connect plugin was seeing `localhost` in the redirect URI instead of the proper domain `openeo-eurac.develop.eoepca.org`. This happened because the Host header from the incoming request was not being preserved correctly.

## Solution Implemented

### 1. Added Missing OIDC Parameters
- Added `scope: "openid email profile"` to the openid-connect plugin
- Added `ssl_verify: false` to avoid SSL validation issues with internal certificates
- Added `set_userinfo_header: true` to pass user information to the backend

### 2. Fixed Host Header Issue
Added a `serverless-pre-function` plugin that runs **before** the openid-connect plugin to explicitly set the correct headers:

```yaml
- name: serverless-pre-function
  enable: true
  config:
    phase: rewrite
    functions:
      - "return function(conf, ctx)
           ngx.req.set_header('Host', 'openeo-eurac.develop.eoepca.org');
           ngx.req.set_header('X-Forwarded-Host', 'openeo-eurac.develop.eoepca.org');
           ngx.req.set_header('X-Forwarded-Proto', 'https');
         end"
```

This ensures that when the openid-connect plugin constructs the redirect URI, it uses the correct hostname instead of `localhost`.

## Files Modified
- `argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml`

## Changes Applied
The configuration has been applied to the cluster:
```bash
kubectl apply -f argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml
```

## How to Test

### Option 1: Monitor logs while testing
Run the monitoring script in one terminal:
```bash
./monitor-openeo-login.sh
```

Then in your browser, access:
```
https://openeo-eurac.develop.eoepca.org
```

Login with Scientificnet-OpenEO and watch the logs.

### Option 2: Direct test
1. Open browser to: `https://openeo-eurac.develop.eoepca.org`
2. You should be redirected to EURAC EDP-PORTAL login
3. Click "Scientificnet-OpenEO"
4. Complete the login
5. You should be redirected back successfully (no 500 error)

### Option 3: Check redirect URI in logs
```bash
kubectl logs -n iam iam-keycloak-apisix-7b8b87bdbf-b978n --tail=50 | grep -i redirect
```

You should now see `openeo-eurac.develop.eoepca.org` in the redirect URI, not `localhost`.

## Expected Behavior After Fix
- ✅ Login page loads with EURAC authentication
- ✅ After successful login, redirect back to OpenEO with correct domain
- ✅ No 500 error during OAuth callback
- ✅ User is authenticated and can access protected OpenEO endpoints

## Verification Commands

Check the plugin configuration:
```bash
# Verify plugin order (serverless-pre-function should be first)
kubectl get apisixroute -n openeo openeo-route -o jsonpath='{.spec.http[1].plugins[*].name}'
# Expected: serverless-pre-function openid-connect cors proxy-rewrite

# Verify serverless-pre-function config
kubectl get apisixroute -n openeo openeo-route -o jsonpath='{.spec.http[1].plugins[0]}' | jq .

# Verify openid-connect has scope
kubectl get apisixroute -n openeo openeo-route -o jsonpath='{.spec.http[1].plugins[1].config.scope}'
# Expected: openid email profile
```

## Troubleshooting

If you still see issues:

1. **Check if valid redirect URIs are configured in Keycloak:**
   - Login to: `https://edp-portal.eurac.edu/auth/admin`
   - Navigate to: Clients → openEO → Settings
   - Verify these redirect URIs exist:
     - `https://openeo-eurac.develop.eoepca.org/*`
     - `https://openeo-eurac.develop.eoepca.org/apisix/redirect`

2. **Check APISIX logs for errors:**
   ```bash
   kubectl logs -n iam iam-keycloak-apisix-7b8b87bdbf-b978n --tail=100
   ```

3. **Check OpenEO backend logs:**
   ```bash
   kubectl logs -n openeo openeo-openeo-argo-5f79d6985d-khdbx -c openeo-argo --tail=100
   ```

4. **Verify the route is active:**
   ```bash
   kubectl get apisixroute -n openeo openeo-route
   ```

## Technical Details

### Why This Happens
APISIX's openid-connect plugin dynamically constructs the redirect URI based on:
1. The `redirect_uri` config parameter (if provided)
2. OR the incoming request's `Host` header + scheme

In this deployment, something in the network path (load balancer, ingress, or proxy) was either:
- Not forwarding the `Host` header correctly
- Forwarding a modified `Host` header (e.g., internal service name)
- Not setting `X-Forwarded-Host` and `X-Forwarded-Proto` headers

The serverless-pre-function plugin forces these headers to the correct values before authentication, ensuring the redirect URI is always constructed correctly.

### Plugin Execution Order
1. **serverless-pre-function** (phase: rewrite) - Sets correct Host headers
2. **openid-connect** - Uses the corrected headers for redirect URI
3. **cors** - Handles CORS headers
4. **proxy-rewrite** - Adds additional request headers

## Next Steps

After verifying the fix works:

1. Commit the changes:
   ```bash
   git add argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml
   git commit -m "Fix OpenEO OIDC redirect URI - force correct Host header

   - Add serverless-pre-function plugin to set Host, X-Forwarded-Host, and X-Forwarded-Proto
   - Add missing scope parameter to openid-connect plugin
   - Add ssl_verify: false and set_userinfo_header: true

   Fixes 500 error during OAuth callback when logging in with Scientificnet-OpenEO"
   ```

2. Push to repository:
   ```bash
   git push origin openeo-redirect-uri
   ```

3. Create/update pull request with test results

## References
- APISIX openid-connect plugin: https://apisix.apache.org/docs/apisix/plugins/openid-connect/
- APISIX serverless plugin: https://apisix.apache.org/docs/apisix/plugins/serverless/
- Keycloak OIDC: https://edp-portal.eurac.edu/auth/realms/edp/.well-known/openid-configuration
