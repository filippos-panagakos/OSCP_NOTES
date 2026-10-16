# Thick Client Application Methodology

## 1. Universal Approach

Thick clients (desktop apps) require a different methodology than web apps. The attack surface spans the binary itself, its network traffic, and its local data storage.

---

## 2. RECON Phase

- [ ] Identify the technology:
```bash
# Linux
file application_binary
strings application_binary | head -50

# Check for embedded files
binwalk application_binary
```
- [ ] Windows tools:
  - **Detect It Easy (DiE)** — identify compiler, packer, language
  - **CFF Explorer** — PE header analysis
  - **PEiD** — packer detection
- [ ] Determine language: Java (.jar/.class), .NET (.exe/.dll), Native (C/C++)

---

## 3. STATIC Analysis

| Language | Tool | Purpose |
|----------|------|---------|
| Java | **JD-GUI** | Decompile .jar/.class to Java source |
| Java | **JADX** | Decompile Android APK / Java |
| .NET | **dnSpy** | Decompile + debug .NET assemblies |
| .NET | **ILSpy** | Decompile .NET (read-only) |
| .NET | **de4dot** | Deobfuscate .NET binaries |
| Native | **Ghidra** | Reverse engineering (free, NSA) |
| Native | **IDA Pro/Free** | Disassembler + decompiler |

### .NET Workflow
```bash
# Deobfuscate first if obfuscated
de4dot application.exe -o application-clean.exe

# Open in dnSpy → browse namespaces → look for:
# - Connection strings
# - Hardcoded credentials
# - API keys
# - Encryption keys
```

### Java Workflow
```bash
# Decompile JAR
jd-gui application.jar
# OR
jadx application.jar -d output/

# Search decompiled source
grep -ri "password\|secret\|key\|token\|jdbc" output/
```

---

## 4. DYNAMIC Analysis

| Tool | Purpose |
|------|---------|
| **ProcMon** (Windows) | Monitor file/registry/network access |
| **x64dbg** | Debug native Windows binaries |
| **Frida** | Dynamic instrumentation (hook functions at runtime) |
| **strace/ltrace** (Linux) | Trace syscalls / library calls |

### ProcMon Filters
- Process Name → is → application.exe
- Operation → contains → WriteFile (find where it writes)
- Path → contains → password (find credential access)

---

## 5. NETWORK Analysis

- [ ] **Wireshark** — capture all traffic from the application
- [ ] **mitmproxy** — intercept HTTPS (need to install CA cert)
- [ ] **Burp Suite** — if app uses HTTP/HTTPS
- [ ] Look for:
  - Plaintext credentials in transit
  - API endpoints being called
  - Hardcoded server addresses
  - Unencrypted sensitive data

---

## 6. EXPLOIT — Common Vulnerabilities

### Hardcoded Credentials
```bash
# Quick scan
strings application.exe | grep -iE "pass|user|key|token|admin|server|jdbc|connection"
```

### DLL Hijacking
- [ ] Use ProcMon to find DLLs loaded from writable paths
- [ ] Place malicious DLL in application directory
- [ ] Application loads attacker DLL → code execution

### Web Vulnerabilities
- If thick client talks to a web API → test for SQLi, XSS, IDOR, etc.

### Session Token Issues
- Predictable tokens
- Tokens stored in plaintext locally
- No token expiration

---

## 7. Language-Specific Attack Chains

### Java Application
```
JAR file → JD-GUI decompile → find hardcoded creds
→ Modify source → javac recompile → jar repackage → bypass auth
```

### .NET Application
```
EXE/DLL → de4dot deobfuscate → dnSpy decompile
→ Find connection strings → Direct DB access
→ OR patch binary in dnSpy → bypass auth checks
```

### Native Application
```
EXE → x64dbg debug → breakpoint at auth function
→ Memory dump at comparison → extract credentials
→ OR Ghidra decompile → find crypto keys
```

---

## 8. Attacking Applications Connecting to Services

### ELF Binary — GDB + PEDA
```bash
# Find connection strings in binary
strings octopus_checker | grep -iE "pass|user|server|connect"

# Debug with GDB
gdb ./octopus_checker
# Install PEDA for enhanced GDB
# Set breakpoint at SQLDriverConnect or similar
break SQLDriverConnect
run
# Read RDX register for connection string
x/s $rdx
```

### .NET DLL — dnSpy Analysis
```
# Open DLL in dnSpy
# Navigate to controller classes
# Search for "connectionString", "SqlConnection", "password"
# Example: MultimasterAPI.dll → ColleagueController → connectionString
```

### Where to Find Binaries
- `C:\Program Files\` and `C:\Program Files (x86)\`
- `/opt/`, `/usr/local/bin/`
- SMB shares
- Web application directories
- Config files: `web.config`, `app.config`, `.env`, `application.properties`

### Quick Methodology
```bash
# 1. Find interesting binaries
find / -name "*.exe" -o -name "*.dll" -o -name "*.jar" -o -name "*.class" 2>/dev/null

# 2. Quick string search
strings binary | grep -iE "pass|user|key|token|admin|server|jdbc|connection"

# 3. If strings not enough → decompile based on language
# 4. If decompile not enough → dynamic debug
```

---

## 9. Decision Tree

```
Thick Client Found
├── Identify language (DiE, file, strings)
├── Java → JD-GUI/JADX → hardcoded creds? → DB access
├── .NET → de4dot → dnSpy → connection strings? → DB access
├── Native → Ghidra/IDA → GDB debug → memory dump creds
├── Network capture → plaintext creds? API endpoints?
├── DLL hijacking possible? → code execution
└── Connecting to services? → extract connection strings → pivot
```
