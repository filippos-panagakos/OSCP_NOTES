# HTB Trea — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux |
| Stack | Node.js / Fastify / JWT / XML (XPath) |

## Attack Flow

Register employee account → Analyze source code → Identify XPath injection in user lookup → Chain type confusion + array bypass on blacklist + XPath injection → Retrieve admin flag

## Reconnaissance

The application is a Node.js/Fastify corporate portal (trea.htb) with JWT authentication. Registration requires a `@trea.htb` email. Users get the `employee` role regardless of what they submit — the server hardcodes it.

### Key Findings from Source Code

1. **Database is XML** — users stored in `users.xml`, queried with XPath (not SQL, not MongoDB)
2. **JWT secret** comes from `process.env.JWT_SECRET` or a random fallback — can't crack it, can't predict it
3. **Admin password** is bcrypt of a randomUUID — uncrackable
4. **`alg: none` attack** blocked — server requires valid signatures (`FAST_JWT_MISSING_SIGNATURE`)
5. **Role injection on register** ignored — server always sets `role: "employee"`
6. **User lookup endpoint** (`GET /api/user?username=X`) returns user data including a `flag` field

## The Vulnerability: XPath Injection via Type Confusion

### Three Security Layers and How Each Was Bypassed

#### Layer 1: Access Check (user.ts)

```typescript
if (typeof username === 'string' && username !== tokenPayload.username) {
    return res.status(403).send({ err: 'Access denied' })
}
```

This prevents you from querying other users — if the username parameter is a string and doesn't match your JWT username, you're blocked.

**Bypass:** Send two `username` parameters in the query string: `?username=test&username=PAYLOAD`. Fastify parses duplicate parameters as an array `["test", "PAYLOAD"]`. Since `typeof array === 'object'` (not `'string'`), the entire if-block evaluates to false and the check is skipped.

#### Layer 2: XPath Injection Blacklist (userService.ts)

```typescript
function looksLikeXPathInjection(input: string): boolean {
    const blacklist = ["'", ';', 'or', 'and', ')', "(", "/" , "doc"];
    return blacklist.some(pattern => input.includes(pattern));
}
```

This blocks common XPath injection characters like single quotes, `or`, `and`, parentheses, and slashes.

**Bypass:** `.includes()` behaves differently on arrays vs strings. On a string, `"admin' or '1'='1".includes("'")` finds the quote character as a substring and returns true (blocked). On an array, `["test", "admin' or '1'='1"].includes("'")` checks if the entire string `"'"` is an array element — it's not, so it returns false (allowed). The blacklist is completely bypassed because it was written assuming string input.

#### Layer 3: XPath Query (userService.ts)

```typescript
const node = xpath.select1(`//user[username='${username}']`, doc as any)
```

User input is concatenated directly into the XPath query string without parameterization.

**Exploitation:** When the array `["test", "admin' or '1'='1"]` is interpolated into the template literal, JavaScript calls `.toString()` which joins array elements with a comma: `test,admin' or '1'='1`. The XPath becomes:

```
//user[username='test,admin' or '1'='1']
```

The injected `'` closes the original quote. `or '1'='1'` is always true. The query matches every user. `xpath.select1` returns the first match — the admin user — whose `flag` field contains the flag.

## The Exploit

```
GET /api/user?username=test&username=admin' or '1'='1
```

URL-encoded:
```
GET /api/user?username=test&username=admin%27%20or%20%271%27%3d%271
```

With a valid JWT Bearer token from a registered employee account.

## What Is XPath Injection

XPath is to XML what SQL is to relational databases — a query language. Instead of `SELECT * FROM users WHERE username='admin'`, XPath uses `//user[username='admin']`. The injection logic is identical to SQLi: unsanitized input concatenated into a query string, break out of the string context with a quote, inject your own logic.

| Backend | Query Language | Injection Type |
|---|---|---|
| SQL databases | SQL | SQLi |
| MongoDB | MongoDB operators/JS | NoSQL injection |
| XML files | XPath | XPath injection |

Same methodology across all three: find where input hits a query, identify the syntax, break out, extract data.

## Methodology Notes

### XPath Injection Detection

- Look for XML-backed applications (XML config files, SOAP endpoints, XML databases)
- Test with single quote `'` in input fields — errors mentioning XPath or XML parsing confirm the backend
- Common payloads: `' or '1'='1`, `' or ''='`, `'] | //user['1'='1`
- If a blacklist blocks quotes, look for type confusion or encoding bypasses

### Type Confusion in Web Apps

- Sending duplicate query parameters (`?param=a&param=b`) creates arrays in most frameworks
- Functions designed for strings behave differently on arrays:
  - `String.includes('x')` checks for substring → catches injection characters
  - `Array.includes('x')` checks for exact element match → misses injection characters inside elements
  - `typeof` returns `'object'` for arrays, not `'string'` → bypasses type checks
- Always test what happens when you send arrays, objects, or unexpected types to parameters
- Bracket syntax (`param[0]=a&param[1]=b`) is another way to force array parsing

### Blacklist Bypasses (General)

- Blacklists are almost always incomplete — look for what's NOT blocked
- Type confusion (arrays vs strings) can bypass string-based filters entirely
- Double encoding, Unicode, null bytes, and case variations are other common bypasses
- Allowlists (only permit known-good characters) are far harder to bypass than blacklists

### Source Code Review Priorities

When you have access to application source code, check in this order:
1. **How is user input used in queries?** — concatenation = injection risk
2. **What sanitization exists?** — blacklist vs allowlist, what's missed
3. **Type handling** — does the code assume input is always a string?
4. **Authentication/authorization checks** — can they be bypassed with unexpected types?
5. **What data is returned?** — sensitive fields (flags, tokens, keys) in responses
