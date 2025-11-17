# Keycloak Configuration Viewer for Windows PowerShell
# Shows all EURAC authentication configuration via REST API

$KEYCLOAK_URL = "http://10.8.244.73:8443"
$REALM = "eoepca"

Write-Host "`n╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           Keycloak EURAC Configuration Viewer (Windows)                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Get admin token
Write-Host "► Getting admin access token..." -ForegroundColor Blue

$tokenBody = @{
    client_id = "admin-cli"
    username = "admin"
    password = "changeme123"
    grant_type = "password"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" -Method Post -Body $tokenBody
    $token = $tokenResponse.access_token
    Write-Host "✓ Admin token obtained`n" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to get admin token: $_" -ForegroundColor Red
    exit 1
}

$headers = @{
    Authorization = "Bearer $token"
}

# Realm Information
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "REALM INFORMATION" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$realm = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM" -Headers $headers
Write-Host "Realm: $($realm.realm)"
Write-Host "Display Name: $($realm.displayName)"
Write-Host "Enabled: $($realm.enabled)"
Write-Host "Login Theme: $($realm.loginTheme)`n"

# EURAC Identity Provider
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "EURAC IDENTITY PROVIDER" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$euracIdp = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/identity-provider/instances/eurac-research" -Headers $headers

Write-Host "`nBasic Configuration:" -ForegroundColor Blue
Write-Host "  Alias:           $($euracIdp.alias)"
Write-Host "  Display Name:    $($euracIdp.displayName)"
Write-Host "  Enabled:         $($euracIdp.enabled)"
Write-Host "  Provider Type:   $($euracIdp.providerId)"
Write-Host "  Trust Email:     $($euracIdp.trustEmail)"
Write-Host "  Store Token:     $($euracIdp.storeToken)"

Write-Host "`nSAML Configuration:" -ForegroundColor Blue
Write-Host "  SSO Service URL: $($euracIdp.config.singleSignOnServiceUrl)"
Write-Host "  Entity ID:       $($euracIdp.config.entityId)"
Write-Host "  Name ID Format:  $($euracIdp.config.nameIDPolicyFormat)"
Write-Host "  Sign Requests:   $($euracIdp.config.wantAuthnRequestsSigned)"
Write-Host "  Validate Sig:    $($euracIdp.config.validateSignature)"
Write-Host "  Post Binding:    $($euracIdp.config.postBindingResponse)`n"

# Attribute Mappers
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "ATTRIBUTE MAPPERS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$mappers = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/identity-provider/instances/eurac-research/mappers" -Headers $headers

Write-Host ""
foreach ($mapper in $mappers) {
    Write-Host "  • $($mapper.name)" -ForegroundColor Cyan
    Write-Host "    SAML Attribute: $($mapper.config.'attribute.name')"
    Write-Host "    User Attribute: $($mapper.config.'user.attribute')"
    Write-Host "    Type: $($mapper.identityProviderMapper)`n"
}

Write-Host "Total Mappers: $($mappers.Count)`n"

# OpenEO OIDC Client
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "OPENEO OIDC CLIENT" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$clients = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/clients" -Headers $headers
$openeoClient = $clients | Where-Object { $_.clientId -eq "openeo" }

Write-Host "`nClient Configuration:" -ForegroundColor Blue
Write-Host "  Client ID:       $($openeoClient.clientId)"
Write-Host "  Name:            $($openeoClient.name)"
Write-Host "  Enabled:         $($openeoClient.enabled)"
Write-Host "  Protocol:        $($openeoClient.protocol)"
Write-Host "  Public Client:   $($openeoClient.publicClient)"
Write-Host "  Standard Flow:   $($openeoClient.standardFlowEnabled)"
Write-Host "  Direct Access:   $($openeoClient.directAccessGrantsEnabled)"

Write-Host "`nRedirect URIs:" -ForegroundColor Blue
foreach ($uri in $openeoClient.redirectUris) {
    Write-Host "  • $uri" -ForegroundColor Cyan
}

Write-Host "`nWeb Origins:" -ForegroundColor Blue
if ($openeoClient.webOrigins) {
    foreach ($origin in $openeoClient.webOrigins) {
        Write-Host "  • $origin" -ForegroundColor Cyan
    }
} else {
    Write-Host "  None configured"
}
Write-Host ""

# Groups
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "GROUPS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$groups = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/groups" -Headers $headers

Write-Host ""
if ($groups.Count -gt 0) {
    foreach ($group in $groups) {
        Write-Host "  • $($group.name)" -ForegroundColor Cyan
        Write-Host "    ID: $($group.id)"
        Write-Host "    Path: $($group.path)`n"
    }
} else {
    Write-Host "  No groups configured`n"
}

# Users
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "USERS" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$users = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/users" -Headers $headers

Write-Host "`nTotal Users: $($users.Count)`n"

if ($users.Count -gt 0) {
    foreach ($user in $users) {
        $email = if ($user.email) { $user.email } else { "no email" }
        Write-Host "  • $($user.username) ($email)" -ForegroundColor Cyan
        Write-Host "    Enabled: $($user.enabled)"
        
        # Convert timestamp to readable date
        if ($user.createdTimestamp) {
            $created = [DateTimeOffset]::FromUnixTimeMilliseconds($user.createdTimestamp).DateTime
            Write-Host "    Created: $created"
        }
        Write-Host ""
    }
}

# OIDC Discovery
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "OIDC DISCOVERY" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

$discovery = Invoke-RestMethod -Uri "$KEYCLOAK_URL/realms/$REALM/.well-known/openid-configuration"

Write-Host "`nKey Endpoints:" -ForegroundColor Blue
Write-Host "  Issuer:          $($discovery.issuer)"
Write-Host "  Authorization:   $($discovery.authorization_endpoint)"
Write-Host "  Token:           $($discovery.token_endpoint)"
Write-Host "  UserInfo:        $($discovery.userinfo_endpoint)"
Write-Host "  JWKs:            $($discovery.jwks_uri)"

Write-Host "`nSupported Features:" -ForegroundColor Blue
Write-Host "  Grant Types:     $($discovery.grant_types_supported -join ', ')"
Write-Host "  Response Types:  $($discovery.response_types_supported -join ', ')`n"

# Summary
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "QUICK LINKS FOR BROWSER TESTING" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

Write-Host "`nEURAC Login URL (test in browser):"
Write-Host "  $KEYCLOAK_URL/realms/$REALM/broker/eurac-research/login" -ForegroundColor Cyan

Write-Host "`nOIDC Discovery:"
Write-Host "  $KEYCLOAK_URL/realms/$REALM/.well-known/openid-configuration" -ForegroundColor Cyan

Write-Host "`nAccount Console (for end users):"
Write-Host "  $KEYCLOAK_URL/realms/$REALM/account/" -ForegroundColor Cyan

Write-Host "`n═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "✓ Configuration retrieval complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════════`n" -ForegroundColor Yellow
