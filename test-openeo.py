import openeo

print("=== OpenEO Programmatic Access Demo ===\n")

# Connect to your OpenEO backend
print("1. Connecting to OpenEO backend...")
connection = openeo.connect("https://openeo-eurac.develop.eoepca.org/openeo/1.1.0/")
print(f"   ✓ Connected to: {connection.capabilities().api_version()}")

# Check what authentication methods are available
print("\n2. Checking available authentication methods...")
import requests
resp = requests.get("https://openeo-eurac.develop.eoepca.org/openeo/1.1.0/credentials/oidc")
providers = resp.json()['providers']
print(f"   Available OIDC providers:")
for provider in providers:
    print(f"   - {provider['id']}: {provider['title']}")
    print(f"     Issuer: {provider['issuer']}")

# List available collections (public endpoint - no auth needed)
print("\n3. Listing available collections (no authentication required)...")
collections = connection.list_collections()
print(f"   Found {len(collections)} collections:")
for coll in collections[:5]:  # Show first 5
    print(f"   - {coll['id']}")
if len(collections) > 5:
    print(f"   ... and {len(collections) - 5} more")

# List available processes (public endpoint - no auth needed)
print("\n4. Listing available processes (no authentication required)...")
processes = connection.list_processes()
print(f"   Found {len(processes)} processes:")
for proc in list(processes)[:5]:  # Show first 5
    print(f"   - {proc['id']}")
if len(processes) > 5:
    print(f"   ... and {len(processes) - 5} more")

print("\n=== For authenticated operations (jobs, user data), you would need to: ===")
print("   connection.authenticate_oidc(provider_id='egi')")
print("   This opens a browser for EURAC Keycloak login")
print("\n   Note: The provider shows as 'EGI Check-in' but uses EURAC Keycloak")
print("   (This is the hardcoded title issue we found in the source code)")
