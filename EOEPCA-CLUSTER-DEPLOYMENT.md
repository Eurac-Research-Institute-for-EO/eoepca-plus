# OpenEO Deployment to EOEPCA Cluster

## What Was Changed

### 1. APISIX Ingress Configuration
**File**: `argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml`

Created APISIX-based ingress with:
- **Public routes**: Discovery endpoints, collections, processes (no auth required)
- **Protected routes**: Job submission, user workspaces (requires EURAC Keycloak login)
- **EURAC Keycloak integration**: Using edp realm and openEO client
- **Automatic TLS**: Let's Encrypt certificate via cert-manager
- **Domain**: `openeo.develop.eoepca.org`

### 2. Helm Values Updated
**File**: `argocd/eoepca/openeo-argoworkflows/parts/helm-openeo-argoworkflows.yaml`

Changed:
- `apiDns`: `127.0.0.1:8000` → `openeo.develop.eoepca.org`
- `apiTLS`: `false` → `true`
- `oidcUrl`: From EGI → `https://edp-portal.eurac.edu/auth/realms/edp`
- `oidcClientId`: Added `"openEO"`
- `oidcClientSecret`: Added `"d00875a6-7967-44fd-b597-bd39fb0f4473"`
- `odicOrganisation`: `egi` → `eurac`

### 3. Kustomization Updated
**File**: `argocd/eoepca/openeo-argoworkflows/parts/kustomization.yaml`

Added `ingress-openeo.yaml` to resources list.

## Prerequisites for Deployment

### ✅ Already Configured
- [x] EURAC Keycloak running at edp-portal.eurac.edu
- [x] Realm `edp` exists
- [x] Client `openEO` configured
- [x] Client secret available
- [x] Login tested and working

### ⚠️ Needs Configuration in Keycloak

**Update Redirect URIs** in the `openEO` client:

1. Log in to Keycloak admin: https://edp-portal.eurac.edu/auth/admin
2. Switch to `edp` realm
3. Go to Clients → `openEO`
4. Add these Valid Redirect URIs:
   ```
   https://openeo.develop.eoepca.org/*
   https://editor.openeo.org/*
   http://localhost:*
   ```
5. Add these Web Origins:
   ```
   https://openeo.develop.eoepca.org
   https://editor.openeo.org
   http://localhost
   ```
6. Save

### 🔧 Needs to Exist in EOEPCA Cluster

**Check these resources exist:**

1. **APISIX installed and running**
   ```bash
   kubectl get pods -n apisix
   ```

2. **cert-manager with Let's Encrypt DNS issuer**
   ```bash
   kubectl get clusterissuer letsencrypt-dns-prod
   ```

3. **DNS configured**
   - `openeo.develop.eoepca.org` must point to the cluster ingress IP

4. **ArgoCD project `eoepca` exists**
   ```bash
   kubectl get appproject eoepca -n argocd
   ```

## Deployment Steps

### Option 1: Deploy via ArgoCD (Recommended)

**If you have access to the EOEPCA cluster:**

1. **Commit and push changes**:
   ```bash
   git add argocd/eoepca/openeo-argoworkflows/
   git commit -m "Configure OpenEO for EOEPCA cluster with EURAC Keycloak"
   git push origin egi-checkin-investigation
   ```

2. **Merge to deploy-develop branch**:
   - Create/update Pull Request
   - Get it reviewed and merged

3. **ArgoCD will automatically deploy** (automated sync is enabled)
   - Or manually sync in ArgoCD UI

### Option 2: Manual Deployment

**If ArgoCD auto-sync doesn't work:**

```bash
# Apply the ArgoCD application
kubectl apply -f argocd/eoepca/openeo-argoworkflows/app-openeo-argoworkflows.yaml

# Or manually apply resources
kubectl apply -k argocd/eoepca/openeo-argoworkflows/parts/
```

### Option 3: Ask Richard/Team Lead

Since your team lead mentioned Richard has access to the EOEPCA cluster:
- Share this document with them
- Ask them to merge the PR and verify deployment
- Or ask them to manually apply the configuration

## Verification Steps

Once deployed, verify:

1. **Pod is running**:
   ```bash
   kubectl get pods -n openeo
   ```

2. **Certificate issued**:
   ```bash
   kubectl get certificate -n openeo openeo-tls
   ```
   Should show `READY=True`

3. **APISIX route created**:
   ```bash
   kubectl get apisixroute -n openeo
   ```

4. **Test public endpoint** (no auth required):
   ```bash
   curl https://openeo.develop.eoepca.org/openeo/1.1.0/
   ```
   Should return: `{"title":"OpenEO ArgoWorkflows",...}`

5. **Test OIDC configuration**:
   ```bash
   curl https://openeo.develop.eoepca.org/openeo/1.1.0/credentials/oidc
   ```
   Should show EURAC Keycloak issuer

6. **Test login in browser**:
   - Go to: https://editor.openeo.org
   - Connect to: https://openeo.develop.eoepca.org/openeo/1.1.0
   - Try to authenticate
   - Should redirect to EURAC Keycloak login

## Comparison: Current VM vs EOEPCA Cluster

| Feature | Current VM (10.8.244.73) | EOEPCA Cluster |
|---------|--------------------------|----------------|
| **URL** | https://10.8.244.73:8443 | https://openeo.develop.eoepca.org |
| **Certificate** | Self-signed (manual) | Let's Encrypt (automatic) |
| **DNS** | IP address only | Proper DNS name |
| **Availability** | Requires port-forward | High availability |
| **Auth** | OpenEO backend handles OIDC | APISIX + OpenEO both enforce auth |
| **Access** | Internal testing only | Public access |
| **Web Editor** | ⚠️ Certificate warnings | ✅ Works seamlessly |

## Troubleshooting

### Certificate Not Issuing

Check cert-manager logs:
```bash
kubectl logs -n cert-manager -l app=cert-manager
kubectl describe certificate -n openeo openeo-tls
```

### APISIX Route Not Working

Check APISIX logs:
```bash
kubectl logs -n apisix -l app.kubernetes.io/name=apisix
kubectl describe apisixroute -n openeo openeo-route
```

### DNS Not Resolving

Verify DNS configuration:
```bash
nslookup openeo.develop.eoepca.org
dig openeo.develop.eoepca.org
```

### Authentication Failing

1. Verify redirect URIs in Keycloak
2. Check APISIX plugin configuration
3. Test OIDC discovery endpoint:
   ```bash
   curl https://edp-portal.eurac.edu/auth/realms/edp/.well-known/openid-configuration
   ```

## Next Steps

1. **Update Keycloak redirect URIs** (see Prerequisites section)
2. **Commit and push changes** to your branch
3. **Ask team lead/Richard** to:
   - Review the changes
   - Verify DNS is configured for openeo.develop.eoepca.org
   - Merge PR to deploy-develop
   - Verify deployment in cluster
4. **Test end-to-end** once deployed
5. **Update documentation** with production URL

## Summary

You now have OpenEO configured for EOEPCA cluster deployment with:
- ✅ EURAC Keycloak authentication (working and tested)
- ✅ APISIX ingress (matching EOEPCA infrastructure patterns)
- ✅ Automatic TLS certificates (Let's Encrypt)
- ✅ Proper domain name (openeo.develop.eoepca.org)
- ✅ Public discovery endpoints + protected execution endpoints
- ✅ CORS support for web clients

The configuration is production-ready. You just need DNS and cluster access to deploy it.
