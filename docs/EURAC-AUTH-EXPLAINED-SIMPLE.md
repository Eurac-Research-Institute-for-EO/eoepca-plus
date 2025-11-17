# 🎓 EURAC Authentication with Keycloak - Explained Simply

## The Problem We're Solving

**Before**: OpenEO was using EGI Check-in directly
- Every user had to have an EGI account
- Limited control over who can access what
- Hard to customize user permissions

**After**: OpenEO uses Keycloak, which connects to EURAC
- EURAC researchers use their existing EURAC credentials
- Better control over permissions and quotas
- Easier to add more organizations later

---

## 🔑 What is Each Component?

### 1. **EURAC SSO** (Identity Provider)
- This is EURAC's login system
- Located at: `sso.eurac.edu`
- EURAC researchers already have accounts here
- Uses SAML protocol (a standard way to share login info)

### 2. **Keycloak** (Identity Broker)
- Think of it as a "translator" between different login systems
- Sits in the EOEPCA platform
- Can talk to many different login systems (EURAC, EGI, Google, etc.)
- Converts everything to one standard format (OIDC/JWT tokens)

### 3. **OpenEO API** (Your Application)
- The actual service researchers want to use
- Processes satellite data
- Needs to know: "Who is this user? What can they do?"

---

## 📖 The Story: How a EURAC Researcher Logs In

Let me walk you through what happens when Maria, a researcher at EURAC, wants to use OpenEO:

### **Step 1: Maria Opens OpenEO**
```
Maria opens her browser → https://openeo.eoepca.org
She sees a login page with a button: "Login with EURAC"
```

### **Step 2: Maria Clicks "Login with EURAC"**
```
OpenEO Web Page → redirects to → Keycloak
Keycloak sees: "Oh, she wants to login with EURAC!"
Keycloak → redirects to → EURAC SSO (sso.eurac.edu)
```

**What's happening behind the scenes:**
- Keycloak creates a SAML request (like a formal letter saying "please authenticate this person")
- This request is sent to EURAC's login system

### **Step 3: Maria Logs In at EURAC**
```
Maria sees EURAC's familiar login page
She enters:
  Username: maria.rossi
  Password: her-eurac-password

EURAC checks: "Is this really Maria? ✓ Yes!"
```

### **Step 4: EURAC Sends Info Back to Keycloak**
```
EURAC → sends SAML Response → Keycloak

The SAML Response contains:
  ✓ Email: maria.rossi@eurac.edu
  ✓ Name: Maria Rossi
  ✓ Role: staff
  ✓ Affiliation: staff@eurac.edu
```

**What's a SAML Response?**
- It's like an official letter from EURAC saying:
  - "Yes, this is Maria Rossi"
  - "Here's what we know about her"
  - Signed with EURAC's digital signature (so Keycloak knows it's real)

### **Step 5: Keycloak Processes the Information**
```
Keycloak receives SAML Response
Keycloak checks:
  ✓ Is the signature valid? (proves it's really from EURAC)
  ✓ Is the user already in our system?

If Maria is NEW:
  → Create user account in Keycloak
  → Copy info from EURAC (email, name, etc.)
  → Assign to "eurac-researchers" group
  → Give her 10 job quota, 100GB storage

If Maria EXISTS:
  → Update her info (in case anything changed)
```

**This is what the attribute mappers do:**
```
EURAC says: "mail = maria.rossi@eurac.edu"
Mapper converts: → Keycloak user.email = maria.rossi@eurac.edu

EURAC says: "givenName = Maria"
Mapper converts: → Keycloak user.firstName = Maria

EURAC says: "eduPersonAffiliation = staff"
Mapper converts: → Keycloak user.affiliation = staff
```

### **Step 6: Keycloak Creates a Token for Maria**
```
Keycloak creates a JWT token (like a digital ID card):
{
  "email": "maria.rossi@eurac.edu",
  "name": "Maria Rossi",
  "username": "maria.rossi@eurac",
  "groups": ["/organizations/eurac", "/openeo/users"],
  "max_jobs": 10,
  "max_storage_gb": 100
}

This token is:
  ✓ Signed (so OpenEO knows it's real)
  ✓ Temporary (expires in 1 hour)
  ✓ Contains everything OpenEO needs to know about Maria
```

### **Step 7: Maria is Redirected Back to OpenEO**
```
Keycloak → redirects back to → OpenEO Web Page
URL includes the JWT token
OpenEO stores the token
Maria is now logged in! 🎉
```

### **Step 8: Maria Uses OpenEO**
```
Maria wants to run a satellite data processing job

OpenEO sends request to API:
  POST /jobs
  Authorization: Bearer <JWT-token>

APISIX Gateway receives request:
  ✓ Validates token signature
  ✓ Checks token is not expired
  ✓ Reads user info from token
  → Passes request to OpenEO API

OpenEO API receives:
  ✓ User: maria.rossi@eurac
  ✓ Groups: eurac-researchers
  ✓ Max jobs: 10
  → Creates the processing job ✓
```

---

## 🎨 Visual Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         THE FLOW                                │
└─────────────────────────────────────────────────────────────────┘

   👩‍🔬 Maria (EURAC Researcher)
    │
    │ 1. "I want to use OpenEO"
    ▼
┌────────────────┐
│ OpenEO Web UI  │
│ (Browser)      │
└────────┬───────┘
         │ 2. Click "Login with EURAC"
         ▼
┌──────────────────────────┐
│     Keycloak             │
│  (EOEPCA Platform)       │
│                          │
│  "She wants EURAC login" │
└────────┬─────────────────┘
         │ 3. SAML Request
         │    (Please authenticate this person)
         ▼
┌──────────────────────────┐
│    EURAC SSO             │
│  sso.eurac.edu           │
│                          │
│  [Username: _______]     │
│  [Password: _______]     │
│         [Login]          │
└────────┬─────────────────┘
         │ Maria enters credentials
         │
         │ 4. SAML Response
         │    (Here's Maria's info + signature)
         ▼
┌──────────────────────────┐
│     Keycloak             │
│                          │
│  ✓ Verify signature      │
│  ✓ Check EURAC is valid  │
│  ✓ Extract attributes:   │
│    - email               │
│    - name                │
│    - affiliation         │
│  ✓ Create/update user    │
│  ✓ Assign to group       │
│  ✓ Generate JWT token    │
└────────┬─────────────────┘
         │ 5. Redirect with JWT token
         ▼
┌──────────────────────────┐
│  OpenEO Web UI           │
│                          │
│  ✅ Maria is logged in!  │
│  Token stored            │
└────────┬─────────────────┘
         │ 6. Maria clicks "Run Job"
         ▼
┌──────────────────────────┐
│   APISIX Gateway         │
│                          │
│  Receives:               │
│    Authorization: Bearer │
│    <JWT-token>           │
│                          │
│  ✓ Validate signature    │
│  ✓ Check expiration      │
│  ✓ Extract user info     │
└────────┬─────────────────┘
         │ 7. Validated request
         ▼
┌──────────────────────────┐
│    OpenEO API            │
│                          │
│  Receives user info:     │
│    - maria.rossi@eurac   │
│    - eurac-researchers   │
│    - max_jobs: 10        │
│                          │
│  ✓ Create job            │
│  ✓ Run processing        │
└──────────────────────────┘
```

---

## 🔍 Let's Look at the Actual Code

### Configuration File 1: Identity Provider (keycloak-idp-eurac.yaml)

This tells Keycloak: "Hey, EURAC is a valid login system you can trust"

```yaml
kind: IdentityProvider
metadata:
  name: eurac-research-saml
spec:
  forProvider:
    alias: eurac-research          # Internal name we use
    displayName: "EURAC Research"  # What users see
    providerId: saml               # Use SAML protocol
    
    config:
      # Where to send login requests
      singleSignOnServiceUrl: "https://sso.eurac.edu/simplesaml/saml2/idp/SSOService.php"
      
      # Where to get EURAC's info (certificates, etc.)
      metadataDescriptorUrl: "https://sso.eurac.edu/simplesaml/saml2/idp/metadata.php"
      
      # Security settings
      validateSignature: "true"      # Check EURAC's signature
      wantAssertionsSigned: "true"   # Require signed responses
```

**In plain English:**
- Name: Call it "eurac-research"
- Protocol: Use SAML
- Where to redirect users: sso.eurac.edu
- Security: Yes, verify everything is really from EURAC

---

### Configuration File 2: Attribute Mappers (keycloak-eurac-mappers.yaml)

These tell Keycloak: "When EURAC sends user info, here's how to store it"

```yaml
# Mapper 1: Email
kind: IdentityProviderMapper
metadata:
  name: eurac-email-mapper
spec:
  forProvider:
    identityProviderMapper: saml-user-attribute-idp-mapper
    config:
      # EURAC sends: attribute "urn:oid:0.9.2342.19200300.100.1.3"
      attribute.name: "urn:oid:0.9.2342.19200300.100.1.3"
      attribute.friendly.name: "mail"
      
      # Save it as: user.email in Keycloak
      user.attribute: "email"
```

**Translation:**
```
When EURAC says: "urn:oid:0.9.2342.19200300.100.1.3 = maria.rossi@eurac.edu"
Keycloak understands: "Oh, that's the email! Save it as user.email"
Result: user.email = "maria.rossi@eurac.edu"
```

**Why the weird "urn:oid:..." names?**
- These are standard codes from eduGAIN (European university federation)
- `urn:oid:0.9.2342.19200300.100.1.3` = email address
- `urn:oid:2.5.4.42` = first name (givenName)
- `urn:oid:2.5.4.4` = last name (surname)
- It's like international postal codes - everyone agrees what they mean

---

### Configuration File 3: Group (keycloak-eurac-group.yaml)

This tells Keycloak: "EURAC users get special benefits"

```yaml
kind: Group
metadata:
  name: eurac-researchers
spec:
  forProvider:
    name: eurac-researchers
    path: /organizations/eurac      # Group hierarchy
    
    attributes:
      max_concurrent_jobs: ["10"]   # Can run 10 jobs at once
      max_storage_gb: ["100"]       # Can use 100GB storage
      priority: ["high"]            # Jobs run faster
```

**What this means:**
- Create a group called "eurac-researchers"
- Anyone in this group gets:
  - 10 concurrent jobs (vs 2 for regular users)
  - 100GB storage (vs 10GB for regular users)
  - High priority processing

---

## 🤔 Common Questions

### Q1: Why use Keycloak instead of connecting directly to EURAC?

**Answer:**
Imagine you run a building with many apartments.

**Without Keycloak (direct connection):**
- Every apartment has its own key system
- Visitors need different keys for each apartment
- You can't control who enters the building
- Hard to track who's inside

**With Keycloak:**
- One main entrance with a receptionist (Keycloak)
- Receptionist checks: "Are you from EURAC? Let me call them..."
- EURAC confirms: "Yes, that's Maria, she works here"
- Receptionist gives Maria a building pass (JWT token)
- Maria can now access apartments she's allowed to enter
- You can easily add more organizations (universities, companies)

---

### Q2: What's the difference between SAML and OIDC?

**SAML** (used by EURAC):
- Older standard, used by universities
- Like sending official letters with wax seals
- XML format (verbose but detailed)

**OIDC** (used by Keycloak → OpenEO):
- Modern standard, used by web apps
- Like sending text messages
- JSON format (compact and easy)

**Keycloak's job:**
- Receives SAML "letters" from EURAC
- Converts to OIDC "text messages" for OpenEO
- OpenEO doesn't need to understand SAML!

---

### Q3: What's a JWT token?

**JWT = JSON Web Token**

Think of it as a digital ID badge that contains:
```json
{
  "sub": "a1b2c3d4...",           // Unique ID
  "email": "maria.rossi@eurac.edu",
  "name": "Maria Rossi",
  "groups": ["/organizations/eurac"],
  "exp": 1699632000,              // Expires in 1 hour
  "iat": 1699628400               // Issued at this time
}
```

**Important features:**
- **Signed**: Like a signature, proves it's from Keycloak
- **Temporary**: Expires after 1 hour
- **Self-contained**: Has all the info OpenEO needs
- **Can't be modified**: Changing anything breaks the signature

**How OpenEO uses it:**
```
User sends: GET /jobs
  Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

OpenEO:
  1. Decode token
  2. Verify signature (is this really from Keycloak?)
  3. Check expiration (is it still valid?)
  4. Read user info (who is this?)
  5. Allow/deny request
```

---

### Q4: What happens after Maria logs in?

**First time Maria logs in:**
```
1. Keycloak creates a new user account
   Username: maria.rossi@eurac
   Email: maria.rossi@eurac.edu
   Name: Maria Rossi

2. Keycloak assigns her to groups:
   - /organizations/eurac
   - /openeo/users

3. Keycloak gives her quotas:
   - max_concurrent_jobs: 10
   - max_storage_gb: 100

4. Keycloak creates a session (valid for 8 hours)

5. Keycloak creates a JWT token (valid for 1 hour)
```

**Next time Maria logs in:**
```
1. Keycloak finds existing user
2. Updates info if anything changed at EURAC
3. Creates new JWT token
4. Maria continues working
```

---

### Q5: What are the attribute mappers actually doing?

Let me show you a real example:

**EURAC sends this SAML Response:**
```xml
<saml:Attribute Name="urn:oid:0.9.2342.19200300.100.1.3" 
                FriendlyName="mail">
    <saml:AttributeValue>maria.rossi@eurac.edu</saml:AttributeValue>
</saml:Attribute>

<saml:Attribute Name="urn:oid:2.5.4.42" 
                FriendlyName="givenName">
    <saml:AttributeValue>Maria</saml:AttributeValue>
</saml:Attribute>

<saml:Attribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.9" 
                FriendlyName="eduPersonScopedAffiliation">
    <saml:AttributeValue>staff@eurac.edu</saml:AttributeValue>
</saml:Attribute>
```

**Attribute mappers convert this to:**
```json
{
  "email": "maria.rossi@eurac.edu",
  "firstName": "Maria",
  "affiliation": "staff@eurac.edu"
}
```

**Then Keycloak creates JWT with:**
```json
{
  "sub": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
  "email": "maria.rossi@eurac.edu",
  "name": "Maria Rossi",
  "preferred_username": "maria.rossi@eurac",
  "groups": ["/organizations/eurac", "/openeo/users"],
  "eurac_affiliation": "staff@eurac.edu"
}
```

**OpenEO API receives this and knows:**
- User: maria.rossi@eurac
- Email: maria.rossi@eurac.edu
- Is EURAC staff: yes
- Can run: 10 jobs
- Storage: 100GB

---

## 🎯 Summary in One Paragraph

When a EURAC researcher wants to use OpenEO, they click "Login with EURAC". Keycloak sends them to EURAC's login page (sso.eurac.edu). After logging in with their EURAC credentials, EURAC sends back a signed message (SAML Response) saying "Yes, this is Maria, here's her info". Keycloak verifies the signature, creates or updates Maria's account, assigns her to the "eurac-researchers" group (giving her 10 jobs and 100GB quota), and creates a JWT token. This token is like a digital ID card that OpenEO can quickly check to know who Maria is and what she can do, without having to ask Keycloak every time.

---

## 📚 The Files We Created

**1. keycloak-idp-eurac.yaml**
   → "EURAC is a trusted login system"

**2. keycloak-eurac-mappers.yaml**
   → "How to read EURAC's user info"

**3. keycloak-eurac-group.yaml**
   → "EURAC users get special quotas"

**4. deploy-eurac-auth.sh**
   → "Script to deploy everything"

**5. Documentation**
   → "How it all works" (this file!)

---

## 🚀 What Happens When You Deploy

```bash
./deploy-eurac-auth.sh
```

**This does:**
1. Checks Keycloak is running ✓
2. Applies: keycloak-idp-eurac.yaml → Keycloak now knows about EURAC
3. Applies: keycloak-eurac-mappers.yaml → Keycloak knows how to read EURAC's info
4. Applies: keycloak-eurac-group.yaml → EURAC users get quotas
5. Shows you the metadata URL to send to EURAC IT

**After deployment:**
- EURAC researchers see "Login with EURAC" button
- They login with EURAC credentials
- They get access to OpenEO automatically
- They get 10 jobs and 100GB storage

---

## 💡 The Big Picture

```
Traditional Way:
User → App
(App has to handle everything)

Modern Way (What we built):
User → Keycloak → App
      ↑
      └── Can connect to: EURAC, EGI, Google, GitHub, etc.

Benefits:
✓ One login for many apps
✓ Users use credentials they already have
✓ Easy to add more organizations
✓ Centralized permission management
✓ Better security
```

---

**Hope this helps! Any questions? 😊**
