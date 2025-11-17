# 🪟 Windows Access Guide

## Quick Start - Open in Windows Browser

The port forwards are now configured for remote access. Open these URLs in your Windows browser:

### ✅ URLs That Work Perfectly

#### 1. Keycloak OIDC Discovery
```
http://10.8.244.73:8443/realms/eoepca/.well-known/openid-configuration
```
Shows complete Keycloak OIDC configuration in JSON format.

#### 2. OpenEO API Documentation
```
http://10.8.244.73:8000/docs
```
Interactive Swagger/FastAPI documentation for OpenEO API.

### ⚠️ URLs That Might Have Issues

#### 3. Keycloak Admin Console (may not load due to JavaScript/SPA issues)
```
http://10.8.244.73:8443/admin/master/console/
```
- Username: `admin`
- Password: `changeme123`

**If this doesn't load:** Use the REST API instead (see below)

#### 4. EURAC Login Test
```
http://10.8.244.73:8443/realms/eoepca/broker/eurac-research/login
```
Will redirect to `https://sso.eurac.edu` for EURAC institutional login.

---

## Port Forward Configuration

The port forwards are running with network binding:

```bash
kubectl port-forward --address 0.0.0.0 -n iam pod/iam-keycloak-0 8443:8080
kubectl port-forward --address 0.0.0.0 -n openeo svc/openeo-openeo-argo 8000:8000
```

**Key difference:**
- `--address 0.0.0.0` makes ports accessible from network (not just localhost)
- Without this flag, only `localhost` on the Linux server can access

---

## Network Requirements

For Windows access to work:

✅ Windows machine and Linux server (`10.8.244.73`) on same network or VPN  
✅ No firewall blocking ports 8443 and 8000  
✅ Network route between machines  

### Troubleshooting Network Access

**Test from Windows PowerShell or Command Prompt:**

1. **Test connectivity:**
   ```powershell
   ping 10.8.244.73
   ```

2. **Test port 8443 (Keycloak):**
   ```powershell
   Test-NetConnection -ComputerName 10.8.244.73 -Port 8443
   ```

3. **Test port 8000 (OpenEO):**
   ```powershell
   Test-NetConnection -ComputerName 10.8.244.73 -Port 8000
   ```

4. **Using curl (if installed):**
   ```powershell
   curl http://10.8.244.73:8443/realms/eoepca/.well-known/openid-configuration
   ```

---

## Alternative: Use REST API Instead of Admin Console

If the admin console doesn't load in your browser, you can use the REST API from Windows:

### PowerShell Example

```powershell
# Get admin token
$body = @{
    client_id = "admin-cli"
    username = "admin"
    password = "changeme123"
    grant_type = "password"
}

$response = Invoke-RestMethod -Uri "http://10.8.244.73:8443/realms/master/protocol/openid-connect/token" -Method Post -Body $body
$token = $response.access_token

# View EURAC Identity Provider
$headers = @{Authorization = "Bearer $token"}
Invoke-RestMethod -Uri "http://10.8.244.73:8443/admin/realms/eoepca/identity-provider/instances/eurac-research" -Headers $headers | ConvertTo-Json
```

### Windows curl Example

```powershell
# Get token
$token = (curl -s -X POST "http://10.8.244.73:8443/realms/master/protocol/openid-connect/token" -d "client_id=admin-cli&username=admin&password=changeme123&grant_type=password" | ConvertFrom-Json).access_token

# View EURAC IdP
curl -H "Authorization: Bearer $token" "http://10.8.244.73:8443/admin/realms/eoepca/identity-provider/instances/eurac-research"
```

---

## What You Should See

### OIDC Discovery Endpoint
Formatted JSON showing:
- Issuer: `https://iam-auth.develop.eoepca.org/realms/eoepca`
- All OIDC endpoints (authorization, token, userinfo, etc.)
- Supported grant types and scopes

### OpenEO API Docs
Swagger UI interface with:
- FastAPI documentation
- List of all endpoints
- Interactive "Try it out" functionality
- Request/response examples

---

## Firewall Check on Linux Server

If Windows cannot connect, check firewall on the Linux server:

```bash
# Check firewall status
sudo ufw status

# If needed, allow the ports (ONLY if firewall is blocking)
sudo ufw allow 8443/tcp
sudo ufw allow 8000/tcp
```

---

## Summary

✅ **Working from Windows:** URLs use server IP `10.8.244.73` instead of `localhost`  
✅ **Port forwards:** Bound to `0.0.0.0` for network access  
✅ **Best URLs to test:**
   - OIDC Discovery: Always works
   - OpenEO Docs: Always works
   - Admin Console: May not load (use REST API)

🎉 **EURAC authentication is fully configured and accessible from Windows!**
