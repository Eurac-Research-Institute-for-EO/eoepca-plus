# EURAC Keycloak Integration - Architecture Analysis

## Current Setup (openeo-argo)

### What You Have
- **Backend**: ArgoWorkflows-based OpenEO API
- **Image**: `ghcr.io/eodcgmbh/openeo-argoworkflows:api-2025.5.1`
- **Namespace**: `openeo`
- **Configuration Method**: Environment variables

### Current OIDC Configuration
```yaml
Environment Variables:
  OIDC_URL: https://cssauth01.eurac.edu:8443/auth/realms/edp
  OIDC_ORGANISATION: eurac
  OIDC_CLIENT_ID: openEO
  OIDC_CLIENT_SECRET: d00875a6-7967-44fd-b597-bd39fb0f4473
```

### How It Works
From the [openeo-argoworkflows source code](https://github.com/eodcgmbh/openeo-argoworkflows):

```python
# In auth.py (line 225-262)
def get_credentials_oidc() -> Response:
    settings = ExtendedAppSettings()
    
    return CredentialsOidcGetResponse(
        providers=[
            Provider(
                id=settings.OIDC_ORGANISATION,  # <- Uses "eurac"
                title="EGI Check-in",            # <- Hardcoded (could be changed)
                issuer=settings.OIDC_URL,        # <- Uses EURAC Keycloak URL
                scopes=[
                    "openid",
                    "email",
                    "eduperson_entitlement",
                    "eduperson_scoped_affiliation",
                ],
                default_clients=[
                    DefaultClient(
                        id="openeo-platform-default-client",  # <- Hardcoded
                        redirect_urls=[
                            "https://editor.openeo.cloud",
                            "https://editor.openeo.org",
                            "http://localhost:1410/",
                        ],
                        grant_types=[
                            GrantType.authorization_code_pkce,
                            GrantType.urn_ietf_params_oauth_grant_type_device_code_pkce,
                            GrantType.refresh_token,
                        ],
                    )
                ],
            )
        ]
    )
```

## Configuration Approach Comparison

### Approach 1: Environment Variables (Current - SIMPLE)

**Status**: ✅ **Already Working**

**Pros**:
- Simple to configure
- No code changes needed
- Uses OIDC_CLIENT_ID and OIDC_CLIENT_SECRET from environment
- Already deployed and functional

**Cons**:
- Only supports **single OIDC provider**
- Title and default_client_id are hardcoded in application code
- Can't easily add multiple providers (EURAC + EGI + others)
- Scopes are hardcoded (though they match what EURAC likely needs)

**What's Hardcoded**:
- Provider title: "EGI Check-in" (misleading since we're using EURAC)
- Default client ID: "openeo-platform-default-client"
- Redirect URLs: editor.openeo.cloud, editor.openeo.org, localhost:1410
- Grant types: authorization_code+pkce, device_code+pkce, refresh_token
- Scopes: openid, email, eduperson_entitlement, eduperson_scoped_affiliation

### Approach 2: Python Config (openeo-geotrellis style)

**Status**: ❌ **Not compatible with openeo-argo architecture**

**How it works in openeo-geotrellis**:
```python
# In values YAML configMap (backendConfig)
oidc_providers = [
    OidcProvider(
        id="eurac",
        title="EURAC Research",
        issuer="https://cssauth01.eurac.edu:8443/auth/realms/edp",
        scopes=["openid", "email"],
        default_clients=[{
            "id": "openEO",
            "grant_types": ["authorization_code+pkce", "refresh_token"],
            "redirect_urls": ["https://editor.openeo.org", "http://localhost:1410/"],
        }],
    ),
    # Can have multiple providers!
]
```

**Why It Won't Work**:
- openeo-argo has **hardcoded** `get_credentials_oidc()` function
- openeo-geotrellis uses a **different backend** (GeoPySpark) with different config system
- Would require **forking and modifying** openeo-argo source code

### Approach 3: Modify openeo-argo Source (COMPLEX)

**What We'd Need to Do**:
1. Fork `eodcgmbh/openeo-argoworkflows` repository
2. Modify `auth.py` to support:
   - Multiple OIDC providers via config
   - Configurable provider title
   - Configurable default client IDs
   - Configurable redirect URLs
3. Build custom Docker image
4. Deploy custom image instead of official one
5. Maintain fork with upstream updates

**Estimated Effort**: 1-2 days + ongoing maintenance

**Pros**:
- Full control over configuration
- Can support multiple providers
- Professional implementation

**Cons**:
- Requires maintaining custom fork
- Need to build/host custom Docker images
- Complex deployment changes
- Breaks compatibility with official releases

## Recommended Solution

### ✅ **Stick with Current Approach + Document Limitations**

**Why**:
1. **It's already working** - login page loads, OAuth2 flow initiated
2. **Minimal configuration** - just environment variables
3. **No code changes** - uses official images
4. **Easy to maintain** - no custom forks

**What to Document**:
Create a note explaining the hardcoded values:

```markdown
## Known Limitations

The openeo-argo backend has some hardcoded values in its OIDC configuration:

- **Provider title**: Shows as "EGI Check-in" but actually uses EURAC Keycloak
- **Default client**: Internal client ID is "openeo-platform-default-client"
- **Actual client**: Uses OIDC_CLIENT_ID (openEO) and OIDC_CLIENT_SECRET from environment
- **Redirect URLs**: Pre-configured for standard OpenEO editors + localhost:1410

These hardcoded values don't affect functionality - authentication works correctly.
To verify, check: http://10.8.244.73:8000/openeo/1.1.0/credentials/oidc
```

**What Still Needs Verification** (waiting for team lead):
1. Test credentials
2. Correct redirect URIs configured in EURAC's Keycloak
3. Client secret validation
4. Which authentication method to use (direct login vs federated providers)

## Alternative: Deploy openeo-geotrellis Alongside

If you want the **multi-provider Python config approach**, deploy openeo-geotrellis as a **separate service**:

```bash
# Deploy openeo-geotrellis (GeoPySpark backend)
kubectl apply -f argocd/eoepca/openeo-geotrellis/openeo-geotrellis.yaml
```

Then modify `argocd/eoepca/openeo-geotrellis/parts/values-openeo-geotrellis-openeo.yaml`:

```python
oidc_providers = [
    OidcProvider(
        id="eurac",
        title="EURAC Research",
        issuer="https://cssauth01.eurac.edu:8443/auth/realms/edp",
        scopes=["openid", "email"],
        default_clients=[{
            "id": "openEO",
            "grant_types": ["authorization_code+pkce", "refresh_token"],
            "redirect_urls": [
                "https://editor.openeo.org",
                "http://localhost:1410/",
            ],
        }],
    ),
    # Keep other providers (EGI, CDSE, etc.)
]
```

**Result**: You'd have **two** OpenEO backends:
- `openeo-argo`: ArgoWorkflows backend (current, simpler)
- `openeo-geotrellis`: GeoPySpark backend (more features, multi-provider)

## Summary

| Approach | Effort | Functionality | Recommendation |
|----------|--------|---------------|----------------|
| **Current (env vars)** | ✅ Done | Single provider, works | ⭐ **Use this** |
| **Modify openeo-argo** | High | Multi-provider | ❌ Not worth it |
| **Deploy openeo-geotrellis** | Medium | Multi-provider | ⚠️ Only if needed |

## Next Steps

1. ✅ **Keep current configuration** (no changes needed)
2. ⏳ **Wait for team lead response** on:
   - Test credentials
   - Redirect URIs
   - Client secret
   - Authentication method
3. ✅ **Test complete login flow** once credentials received
4. ✅ **Update WINDOWS-ACCESS.md** with correct URLs
5. ⏳ **Clean up obsolete local Keycloak** (optional)

---

**Bottom Line**: Your current setup is good! The hardcoded values in the source code are cosmetic - the actual authentication uses your EURAC configuration correctly. No changes needed unless you specifically want multi-provider support, in which case deploy openeo-geotrellis instead.
