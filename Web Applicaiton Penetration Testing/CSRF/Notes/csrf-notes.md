## Cross-Site Request Forgery (CSRF) — Theory Notes


### What Is CSRF

CSRF is a vulnerability that lets an attacker trick a logged-in user into performing actions they didn't intend — changing their email, password, making a transfer, etc. The attacker crafts a malicious page that fires a request to the vulnerable site. The victim's browser automatically attaches their session cookie, so the server thinks it's a legitimate request.

If the victim has a privileged role (admin), the attacker can potentially control the entire application.

### Three Conditions Required

For CSRF to work, ALL three must be true:

1. **A relevant action exists** — something worth triggering (email change, password change, fund transfer, privilege escalation)
2. **Cookie-based session handling** — the app identifies users solely through session cookies, no other validation
3. **No unpredictable parameters** — the attacker can determine or guess every parameter in the request (if the form requires the current password, CSRF won't work)

### Basic CSRF Attack

The vulnerable request looks like:
```
POST /my-account/change-email HTTP/1.1
Cookie: session=abc123
Content-Type: application/x-www-form-urlencoded

email=victim@normal.com
```

The exploit page:
```html
<html>
  <body>
    <form action="https://vulnerable-site.com/my-account/change-email" method="POST">
      <input type="hidden" name="email" value="attacker@evil.com" />
    </form>
    <script>document.forms[0].submit();</script>
  </body>
</html>
```

Host this on an exploit server, lure the victim to visit it, done.

### Delivering the Exploit

- Host it on your own server and send the link (email, social media, etc.)
- Inject it into a site the victim visits (comment section, forum post)
- For GET-based actions, a simple `<img>` tag works: `<img src="https://target.com/change-email?email=pwned@evil.com">`

---

## CSRF Defenses and How to Bypass Them

### Defense 1: CSRF Tokens

A unique, unpredictable value generated server-side and included in each sensitive request. The server rejects requests with a missing or wrong token.

#### Bypass: Validation depends on request method
The server only validates the token on POST requests. Switch to GET:
```
GET /my-account/change-email?email=pwned@evil.com HTTP/1.1
```
No token needed. Your exploit just uses an `<img>` tag or a GET form.

#### Bypass: Validation depends on token being present
The server validates the token IF it's there, but skips validation if the parameter is omitted entirely. Just remove the token parameter from your exploit form.

#### Bypass: Token not tied to user session
The server checks that the token is valid, but doesn't verify it belongs to the specific user making the request. The attacker can use their OWN valid token in the exploit — log in, grab your token, plug it into the CSRF payload aimed at the victim.

#### Bypass: Token tied to a non-session cookie
The token is validated against a cookie that isn't the main session cookie (e.g., a `csrfKey` cookie). If you can set cookies on the victim's browser (via a cookie-setting vulnerability like CRLF injection or a subdomain XSS), you set your own `csrfKey` cookie on the victim and use the matching token in the form.

#### Bypass: Token duplicated in cookie
The "double submit" pattern — the app just checks if the token in the request body matches the token in the cookie, with no server-side record. If you can set a cookie on the victim's browser, you set both the cookie and the form parameter to any matching value you control.

---

### Defense 2: SameSite Cookies

A browser-level mechanism that controls whether cookies are sent with cross-site requests.

#### Key Concepts

**Site vs Origin:**
- **Site** = scheme + top-level domain + one label (e.g., `https://example.com`). Subdomains are same-site.
- **Origin** = scheme + full hostname + port. Stricter than site.

**SameSite values:**
- **Strict** — cookie is NEVER sent on cross-site requests. Not even if the user clicks a link to the target site from another site.
- **Lax** — cookie IS sent on cross-site requests IF it's a top-level navigation (clicking a link) AND uses GET. Not sent on POST, iframes, AJAX, or `<img>` tags.
- **None** — cookie is always sent cross-site (requires `Secure` flag). Basically no CSRF protection.

Chrome defaults to **Lax** if no SameSite attribute is set (since 2021). There's a 2-minute window after setting a cookie where Lax isn't enforced, to avoid breaking SSO flows — this can sometimes be exploited.

#### Bypass: SameSite Lax via GET + method override

If the app accepts `_method` parameter overrides:
```
GET /my-account/change-email?email=pwned@evil.com&_method=POST HTTP/1.1
```
The browser treats it as GET (so Lax allows the cookie), but the server-side framework interprets it as POST. Exploit with a simple link click or top-level redirect.

#### Bypass: SameSite Strict via client-side redirect gadget

SameSite Strict blocks all cross-site requests. But if you find a page on the target site that does a **JavaScript-based redirect** using user input (like `window.location = "/path/" + userParam`), you have a gadget.

The chain:
1. Victim clicks a link to the target site (cross-site navigation — cookie included for Strict because it's a top-level navigation TO the target)
2. The target page's JavaScript reads a parameter and redirects via `window.location`
3. Path traversal in the parameter breaks out to `/my-account/change-email?email=...&submit=1`
4. This is now a **same-site** navigation (JS redirect on the same domain), so the cookie rides along

Example exploit:
```html
<script>
window.location = "https://target.com/post/comment/confirmation?postId=../my-account/change-email?email=pwned%40evil.com%26submit=1";
</script>
```

Key insight: JavaScript redirects (`window.location`, `document.location`) are treated as same-site navigations by the browser, unlike server-side 302 redirects.

#### Bypass: SameSite Strict via sibling domain

If a sibling subdomain (e.g., `cms.target.com`) has an XSS or open redirect, you can use it as a launchpad. Subdomains are **same-site**, so requests originating from there carry the cookie.

---

### Defense 3: Referer Header Validation

The server checks the HTTP `Referer` header to confirm the request came from its own domain.

#### Bypass: Suppressing the Referer header

Some servers only validate the Referer IF it's present. If it's missing, they skip the check.

Add this to your exploit page `<head>`:
```html
<meta name="referrer" content="never">
```

The browser won't send a Referer header. The server sees no header, skips validation, processes the request.

#### Bypass: Weak substring validation

The server checks if the Referer **contains** its domain name (substring check, not exact match).

Use `history.pushState` to rewrite your exploit page's URL to include the target domain in the query string:
```html
<html>
  <head>
    <meta name="referrer" content="unsafe-url">
  </head>
  <body>
    <form action="https://target.com/my-account/change-email" method="POST">
      <input type="hidden" name="email" value="pwned@evil.com" />
    </form>
    <script>
      history.pushState("", "", "/?target.com");
      document.forms[0].submit();
    </script>
  </body>
</html>
```

Also set the response header `Referrer-Policy: unsafe-url` on the exploit server, because modern browsers strip query strings from the Referer by default. This forces the browser to send the full URL including `?target.com`.

---

## CSRF Checklist — What to Look For

1. Identify state-changing actions (email change, password change, settings, transfers)
2. Check if the request has a CSRF token — if yes, test all the token bypass methods
3. Check the cookie's SameSite attribute — if Strict/Lax, look for redirect gadgets or method overrides
4. Check if Referer validation is in place — test suppression and substring tricks
5. Always check: does the server validate on ALL methods? Does it skip validation when a parameter is missing?
6. Look for cookie-setting vectors (CRLF injection, subdomain XSS) for double-submit bypasses
7. Look for client-side redirect gadgets (JS using URL parameters in `window.location`) for SameSite Strict bypass
