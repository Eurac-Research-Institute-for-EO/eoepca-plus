# Browser-Based Login Testing Guide

## Current Status
✅ **EURAC Login Page Loading Successfully!**
- The screenshot shows the correct EURAC EDP-PORTAL login page
- All 3 authentication methods are visible:
  - Direct username/password
  - OpenDataHub@NOI
  - Scientificnet-OpenEO

## HTTP vs HTTPS Issue

The OpenEO Web Editor blocks HTTP connections by default for security. Here are your options:

### Solution 1: Enable HTTP in Web Editor (Recommended for Testing)

1. Open https://editor.openeo.org
2. Click the **Settings/Gear icon** (⚙️) in the top-right corner
3. Look for one of these options:
   - "Allow insecure HTTP connections"
   - "Development Mode"
   - "Experimental Features"
4. **Enable** the option to allow HTTP
5. Try connecting again to: `http://10.8.244.73:8000/openeo/1.1.0`

### Solution 2: Manual OAuth Flow Testing (Works Right Now)

You can manually complete the login to test if everything works:

#### Step 1: Start the Login Flow

Open this URL in your browser:
```
https://cssauth01.eurac.edu:8443/auth/realms/edp/protocol/openid-connect/auth?response_type=code&client_id=openEO&redirect_uri=https://editor.openeo.org&scope=openid%20email&state=test123
```

#### Step 2: Login with Your Credentials

Choose one of the authentication methods:
- **Direct Login**: Enter your EURAC username and password
- **OpenDataHub@NOI**: Click the button if you have NOI credentials
- **Scientificnet-OpenEO**: Click if you have Scientificnet credentials

#### Step 3: Check the Redirect

After successful login, you'll be redirected to:
```
https://editor.openeo.org/?code=XXXXX&state=test123
```

The `code=XXXXX` is the authorization code - this proves the OAuth flow is working!

#### Step 4: Exchange Code for Token (Manual Test)

Copy the authorization code from the URL and run this from your Linux server:

```bash
# Replace YOUR_CODE_HERE with the actual code from the redirect URL
CODE="YOUR_CODE_HERE"

curl -X POST "https://cssauth01.eurac.edu:8443/auth/realms/edp/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "client_id=openEO" \
   -d "client_secret=8f7f2fb0-4347-44be-b5be-d752cbd3de11" \
  -d "code=$CODE" \
  -d "redirect_uri=https://editor.openeo.org"
```

If successful, you'll receive:
```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 300,
  "refresh_token": "...",
  "scope": "openid email"
}
```

This confirms the full authentication flow works!

### Solution 3: Setup HTTPS for OpenEO (Production Solution)

For production use, you should expose OpenEO via HTTPS. Options:

#### Option A: Use Ingress with TLS

```bash
# Check if you have ingress controller
kubectl get ingress -A

# If you have cert-manager, create an ingress
```

#### Option B: Use kubectl port-forward with local HTTPS proxy

Use a local proxy like `nginx` or `caddy` to add HTTPS:

```bash
# Install caddy (if not installed)
# Then create Caddyfile:
cat > Caddyfile << 'EOF'
https://localhost:8443 {
    tls internal
    reverse_proxy http://10.8.244.73:8000
}
EOF

# Run caddy
caddy run
```

Then connect to `https://localhost:8443/openeo/1.1.0` in the web editor.

## What to Test Next

Once you can complete the login (with any method above):

1. ✅ Verify login page loads (DONE - screenshot confirms this!)
2. ⏳ Complete login with test credentials
3. ⏳ Verify redirect includes authorization code
4. ⏳ Exchange code for access token
5. ⏳ Test authenticated API call to OpenEO
6. ⏳ Submit a test processing job

## Questions for Team Lead

Since the login page is loading correctly, please confirm:

1. **Which authentication method should be used?**
   - Direct username/password to edp realm?
   - OpenDataHub@NOI federated login?
   - Scientificnet-OpenEO federated login?

2. **Redirect URI configuration**
   - Is `https://editor.openeo.org` configured in the openEO client?
   - Should we add `http://localhost:1410/` for desktop client testing?

3. **Test credentials**
   - Can you provide test credentials for the chosen authentication method?

4. **Production URL**
   - What will be the production HTTPS URL for OpenEO?
   - Should we set up an ingress with TLS certificate?
