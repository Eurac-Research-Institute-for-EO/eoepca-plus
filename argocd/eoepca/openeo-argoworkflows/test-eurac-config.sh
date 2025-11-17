#!/usr/bin/env bash

# EURAC Authentication Configuration Test Script
# Run this before pushing changes to verify configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║     EURAC Authentication Configuration - Pre-Push Tests         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED=0

# Test 1: YAML Syntax Validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 1: YAML Syntax Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FILES=(
    "parts/keycloak-idp-eurac.yaml"
    "parts/keycloak-eurac-mappers.yaml"
    "parts/keycloak-eurac-group.yaml"
)

for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo -n "Checking $file... "
        if python3 -c "import yaml; yaml.safe_load_all(open('$file'))" 2>/dev/null; then
            echo -e "${GREEN}✅ Valid${NC}"
        else
            echo -e "${RED}❌ Invalid YAML${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}❌ File not found: $file${NC}"
        FAILED=$((FAILED + 1))
    fi
done

# Test 2: Resource Structure Validation
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 2: Resource Structure Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

python3 << 'PYEOF'
import yaml
import sys

files_config = {
    'parts/keycloak-idp-eurac.yaml': {
        'kind': 'IdentityProvider',
        'expected_name': 'eurac-research-saml',
        'required_fields': ['spec.forProvider.alias', 'spec.forProvider.config.singleSignOnServiceUrl']
    },
    'parts/keycloak-eurac-mappers.yaml': {
        'kind': 'IdentityProviderMapper',
        'expected_count': 7
    },
    'parts/keycloak-eurac-group.yaml': {
        'kind': 'Group',
        'expected_name': 'eurac-researchers'
    }
}

all_ok = True

for file_path, config in files_config.items():
    try:
        with open(file_path, 'r') as f:
            docs = list(yaml.safe_load_all(f))
            docs = [d for d in docs if d is not None]
            
            if config['kind'] == 'IdentityProviderMapper':
                if len(docs) == config['expected_count']:
                    print(f"✅ {file_path}: Found {len(docs)} mappers")
                else:
                    print(f"❌ {file_path}: Expected {config['expected_count']} mappers, found {len(docs)}")
                    all_ok = False
            else:
                doc = docs[0]
                kind = doc.get('kind')
                name = doc.get('metadata', {}).get('name')
                
                if kind == config['kind']:
                    print(f"✅ {file_path}: kind={kind}")
                else:
                    print(f"❌ {file_path}: Expected kind={config['kind']}, got {kind}")
                    all_ok = False
                    
                if 'expected_name' in config:
                    if name == config['expected_name']:
                        print(f"   ✅ Name: {name}")
                    else:
                        print(f"   ❌ Expected name={config['expected_name']}, got {name}")
                        all_ok = False
                        
    except Exception as e:
        print(f"❌ {file_path}: {e}")
        all_ok = False

sys.exit(0 if all_ok else 1)
PYEOF

if [[ $? -ne 0 ]]; then
    FAILED=$((FAILED + 1))
fi

# Test 3: EURAC SSO Endpoint Validation
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 3: EURAC SSO Endpoint Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "Checking EURAC metadata endpoint... "
if timeout 10 curl -s -f -o /dev/null https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php 2>/dev/null; then
    echo -e "${GREEN}✅ Accessible${NC}"
else
    echo -e "${YELLOW}⚠️  Slow or unreachable (may work in production)${NC}"
fi

echo -n "Checking EURAC SSO service... "
if timeout 10 curl -s -f -o /dev/null https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php 2>/dev/null; then
    echo -e "${GREEN}✅ Accessible${NC}"
else
    echo -e "${YELLOW}⚠️  Endpoint exists but may require SAML request${NC}"
fi

# Test 4: Configuration Values Check
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 4: Configuration Values Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

python3 << 'PYEOF'
import yaml

with open('parts/keycloak-idp-eurac.yaml', 'r') as f:
    idp = yaml.safe_load(f)
    config = idp['spec']['forProvider']['config']
    
    checks = {
        'SSO URL': config.get('singleSignOnServiceUrl', ''),
        'Metadata URL': config.get('metadataDescriptorUrl', ''),
        'Entity ID': config.get('entityId', ''),
        'Validate Signature': config.get('validateSignature', ''),
        'Want Assertions Signed': config.get('wantAssertionsSigned', ''),
    }
    
    for name, value in checks.items():
        if value and 'eurac' in str(value).lower():
            print(f"✅ {name}: {value}")
        elif value:
            print(f"⚠️  {name}: {value}")
        else:
            print(f"❌ {name}: MISSING")
PYEOF

# Test 5: Documentation Validation
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 5: Documentation Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DOCS=(
    "../../../docs/eurac-authentication-setup.md"
    "../../../docs/keycloak-integration-strategy.md"
    "EURAC-README.md"
    "../../../EURAC-CONFIGURATION-SUMMARY.md"
)

for doc in "${DOCS[@]}"; do
    if [[ -f "$doc" ]]; then
        lines=$(wc -l < "$doc")
        echo -e "${GREEN}✅ $doc${NC} ($lines lines)"
    else
        echo -e "${RED}❌ Missing: $doc${NC}"
        FAILED=$((FAILED + 1))
    fi
done

# Test 6: Script Executability
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 6: Script Executability"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -x "deploy-eurac-auth.sh" ]]; then
    echo -e "${GREEN}✅ deploy-eurac-auth.sh is executable${NC}"
else
    echo -e "${RED}❌ deploy-eurac-auth.sh is not executable${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 7: Git Status Check
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 7: Git Status Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd ../../..
NEW_FILES=$(git status --short | grep "^??" | wc -l)
MODIFIED_FILES=$(git status --short | grep "^ M" | wc -l)
STAGED_FILES=$(git status --short | grep "^M" | wc -l)

echo "New files: $NEW_FILES"
echo "Modified files: $MODIFIED_FILES"
echo "Staged files: $STAGED_FILES"

if [[ $NEW_FILES -gt 0 ]] || [[ $MODIFIED_FILES -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Uncommitted changes detected${NC}"
    echo ""
    echo "Files to commit:"
    git status --short | grep -E "^\?\?|^ M|^M" | head -15
fi

# Final Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                        TEST SUMMARY                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo ""
    echo "Your EURAC authentication configuration is ready to push!"
    echo ""
    echo "Next steps:"
    echo "  1. Review the changes: git status"
    echo "  2. Add files: git add docs/ argocd/eoepca/openeo-argoworkflows/"
    echo "  3. Commit: git commit -m 'feat: add EURAC SAML authentication'"
    echo "  4. Push: git push origin egi-checkin-investigation"
    exit 0
else
    echo -e "${RED}❌ $FAILED TEST(S) FAILED${NC}"
    echo ""
    echo "Please fix the issues above before pushing."
    exit 1
fi
