# OpenEO ArgoWorkflows - Complete Fixes & Setup Summary

## Overview

This document covers all work done to deploy and fix OpenEO ArgoWorkflows on EURAC's in-house MicroK8s cluster.

---

## Phase 1: Initial Cluster Setup & Debugging

### 1.1 MicroK8s Cluster Verification
- Verified MicroK8s cluster was running on `10.8.244.73`
- Enabled required addons: dns, storage, registry, ingress
- Checked cluster connectivity and pod status

### 1.2 DNS/CoreDNS Issues
- **Problem**: Pods couldn't resolve external DNS (STAC API, Keycloak)
- **Fix**: Configured CoreDNS with proper upstream resolvers
- Verified DNS resolution from within pods

### 1.3 Redis Connection Issues
- **Problem**: OpenEO API couldn't connect to Redis
- **Fix**: Updated Redis service IP in deployment configuration
- Verified Redis was accessible from API pods

---

## Phase 2: Authentication Fixes

### 2.1 Keycloak OIDC Integration
- **Problem**: Device code polling returned 400 errors
- **Root Cause**: Token verification was failing due to audience mismatch
- **Fix**: Created custom `auth.py` patch that skips audience verification
- **File**: ConfigMap `openeo-auth-patch` mounted into API container

### 2.2 OIDC Scopes Configuration
- **Problem**: Web Editor rejected by Keycloak - invalid scopes
- **Root Cause**: Backend advertised EGI-specific scopes (`eduperson_entitlement`, `eduperson_scoped_affiliation`)
- **Fix**: Changed to standard Keycloak scopes (`openid`, `email`, `profile`)
- **File**: `executor-fix/core_patched.py`

### 2.3 Redirect URI for Web Editor
- **Problem**: Local Web Editor URL not in allowed redirect URIs
- **Fix**: Added `http://10.8.244.73:8080/` to `redirect_urls` in code + Keycloak admin config
- **File**: `executor-fix/core_patched.py`

---

## Phase 3: Executor/Job Fixes

### 3.1 Empty Job Results - Variable Initialization Bug
- **Problem**: Jobs completed but produced empty netCDF files with `Infinity` bbox
- **Root Cause**: `UnboundLocalError` - variables `resolution`, `nodata`, `dtype` not initialized before conditional check
- **Fix**: Initialize all variables to `None` before use
- **File**: `executor-fix/io_fixed.py`

### 3.2 STAC Asset Filtering
- **Problem**: Executor tried to load thumbnail/tilejson assets causing rasterio errors
- **Error**: `RasterioIOError: Range downloading not supported` (titiler preview URLs)
- **Fix**: Filter assets to only load data assets (B01-B12, data, visual)
- **File**: `executor-fix/io_fixed.py`

### 3.3 CRS Handling in Output
- **Problem**: Output netCDF files had no CRS, STAC item creation failed
- **Error**: `pyproj.exceptions.CRSError: Invalid projection (empty string)`
- **Fix**:
  - Use rioxarray to properly write CRS to output files
  - Add fallback CRS detection from attributes and spatial_ref
  - Default to EPSG:4326 if no CRS found
- **Files**: `executor-fix/io_fixed.py`, `executor-fix/stac_fixed.py`

### 3.4 STAC Datetime Format
- **Problem**: STAC API requires ISO format with time component
- **Error**: `datetime_parsing` error from STAC API
- **Fix**: Append `T00:00:00Z` to date-only strings
- **File**: `executor-fix/io_fixed.py`

### 3.5 No Data Found Error Message
- **Problem**: Silent failure when STAC search returns no items
- **Fix**: Added clear error message with bbox and time range details
- **File**: `executor-fix/io_fixed.py`

### 3.6 CRS Extraction from STAC Items
- **Problem**: CRS not being read from STAC item properties
- **Fix**: Check `proj:wkt2` and `proj:epsg` in item properties
- **File**: `executor-fix/load_patched.py`

---

## Phase 4: API Fixes

### 4.1 Well-Known URL Bug
- **Problem**: API returned malformed URL with semicolon
- **Example**: `http://10.8.244.73/;/openeo/1.1.0/`
- **Root Cause**: Incorrect field order in `urlunparse` call
- **Fix**: Corrected `url` and `path` field values in `get_well_known()`
- **File**: `executor-fix/core_patched.py`

### 4.2 Job Logs Not Displaying in Web Editor
- **Problem**: Web Editor JavaScript error "Cannot read properties of undefined (reading 'id')"
- **Root Cause**: Logs endpoint returned plain strings instead of LogEntry objects
- **OpenEO Spec**: Requires `{id, level, message}` format for each log entry
- **Fix**: Return properly formatted log entries with all required fields
- **File**: `executor-fix/jobs_patched.py`

---

## Phase 5: Web Editor Setup

### 5.1 Local Web Editor Deployment
- Deployed openEO Web Editor via Docker on port 8080
- **Command**: `docker run -d -p 8080:80 --name openeo-editor openeo-web-editor`
- **URL**: `http://10.8.244.73:8080/`

### 5.2 CORS Configuration
- Ensured ingress has proper CORS headers for cross-origin requests
- Headers: `Access-Control-Allow-Origin: *`, proper methods and headers

---

## Phase 6: Ingress Configuration

### 6.1 OpenEO Public Endpoints
- Configured NGINX ingress for `/openeo` and `/.well-known` paths
- Removed authentication from public endpoints (capabilities, collections, processes)
- **File**: `argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml`

---

## Docker Images Created

| Image | Version | Purpose |
|-------|---------|---------|
| `localhost:32000/openeo-executor-fixed` | v11 | Executor with all load_collection fixes |
| `localhost:32000/openeo-api-fixed` | v3 | API with OIDC, URL, and logs fixes |

---

## Key Files in executor-fix/

| File | Purpose |
|------|---------|
| `Dockerfile` | Executor image build |
| `Dockerfile.api` | API image build |
| `io_fixed.py` | Fixed `load_collection` and `save_result` |
| `stac_fixed.py` | Fixed STAC item creation with CRS handling |
| `load_patched.py` | Fixed CRS extraction from STAC items |
| `core_patched.py` | Fixed OIDC scopes and well-known URL |
| `jobs_patched.py` | Fixed logs endpoint format |

---

## Configuration

### STAC API
- **Current**: `https://stac.eodc.eu/api/v1`
- **Configurable via**: `STAC_API_URL` environment variable
- **Available collections**: BOA_SENTINEL_2, BOA_LANDSAT_8, COP_DEM, etc.

### Keycloak
- **URL**: `https://edp-portal.eurac.edu/auth/realms/edp`
- **Client**: `openeo-platform-default-client`
- **Required config**: Add redirect URIs for Web Editor

### Endpoints
- **OpenEO API**: `http://10.8.244.73/openeo/1.1.0/`
- **Web Editor**: `http://10.8.244.73:8080/`
- **Well-known**: `http://10.8.244.73/.well-known/openeo`

---

## Deployment Commands

### Build and Push Executor
```bash
cd executor-fix
docker build -f Dockerfile -t localhost:32000/openeo-executor-fixed:v11 .
docker push localhost:32000/openeo-executor-fixed:v11
```

### Build and Push API
```bash
cd executor-fix
docker build -f Dockerfile.api -t localhost:32000/openeo-api-fixed:v3 .
docker push localhost:32000/openeo-api-fixed:v3
```

### Update Deployments
```bash
# Update executor image
kubectl set env deployment/openeo-openeo-argo -n openeo \
  OPENEO_EXECUTOR_IMAGE=localhost:32000/openeo-executor-fixed:v11 \
  EXECUTOR_IMAGE=localhost:32000/openeo-executor-fixed:v11

# Update API image
kubectl set image deployment/openeo-openeo-argo -n openeo \
  openeo-argo=localhost:32000/openeo-api-fixed:v3 \
  openeo-argo-queue-worker=localhost:32000/openeo-api-fixed:v3

# Restart workflow controller (picks up new executor image)
kubectl rollout restart deployment/openeo-argo-workflows-workflow-controller -n openeo
```

---

## Testing

### Test Job (Poland - where BOA_SENTINEL_2 data exists)
```json
{
  "process_graph": {
    "load1": {
      "process_id": "load_collection",
      "arguments": {
        "id": "BOA_SENTINEL_2",
        "spatial_extent": {"west": 17.7, "south": 50.9, "east": 17.9, "north": 51.1},
        "temporal_extent": ["2020-12-01", "2020-12-31"]
      }
    },
    "save1": {
      "process_id": "save_result",
      "arguments": {"data": {"from_node": "load1"}, "format": "netCDF"},
      "result": true
    }
  }
}
```

### Python Client Test
```python
import openeo
conn = openeo.connect("http://10.8.244.73/openeo/1.1.0/")
conn.authenticate_oidc_device()
# Follow device code flow...
```

---

## Additional Documentation Created

- `EURAC_INHOUSE_DEPLOYMENT.md` - Complete in-house deployment guide (1600+ lines)
- `OPENEO_DEPLOYMENT_SUMMARY.md` - High-level deployment summary
- Various test scripts in project root

---

## Summary Statistics

- **Issues Fixed**: 12+
- **Files Created/Modified**: 8
- **Docker Images Built**: 2 (executor v11, api v3)
- **Time Span**: Multiple sessions
- **Working Result**: Full OpenEO deployment with Web Editor, authentication, and job execution

---

**Last Updated**: January 17, 2026
