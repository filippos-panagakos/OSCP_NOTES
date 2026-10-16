# Application Hardening & Honorable Mentions

## 1. General Hardening Principles

- [ ] Implement strong authentication (disable default creds, enforce MFA)
- [ ] Apply principle of least privilege for access controls
- [ ] Disable unsafe features, debug modes, and unnecessary modules
- [ ] Keep applications updated and patched
- [ ] Maintain regular backups
- [ ] Deploy security monitoring, WAF, and logging
- [ ] Integrate with LDAP/AD for centralized auth
- [ ] Restrict management interfaces to localhost / VPN only

---

## 2. Per-Application Hardening Tips

| Application | Key Hardening Step |
|-------------|-------------------|
| **WordPress** | Install WordFence plugin, disable XML-RPC, remove unused themes/plugins |
| **Joomla** | AdminExile plugin (secret key for admin URL), disable user registration |
| **Drupal** | Hide login page, disable PHP Filter, restrict user registration |
| **Tomcat** | Restrict /manager to localhost only, remove default apps, change default creds |
| **Jenkins** | Matrix Authorization Strategy plugin, disable Script Console for non-admins |
| **Splunk** | Enforce license, restrict app installation, disable unnecessary inputs |
| **PRTG** | Change default prtgadmin password immediately, restrict notification scripts |
| **osTicket** | Limit internet-facing exposure, restrict ticket submission |
| **GitLab** | Require admin approval for new signups, disable public registration |

---

## 3. Honorable Mentions — Other Applications to Know

### Apache Axis2
- AAR (Axis Archive) webshell upload
- Similar to WAR deployment on Tomcat
- Default creds: `admin:axis2`

### IBM WebSphere
- WAR file deployment (like Tomcat)
- Default creds: `system:manager`
- Admin console typically on port 9060

### Elasticsearch
- Often deployed without authentication
- Default port: 9200
- `curl http://TARGET:9200/_cat/indices` — list all indices
- `curl http://TARGET:9200/INDEX/_search?pretty` — dump data
- May contain sensitive indexed data

### Zabbix
- Monitoring platform
- Known for: SQLi, XSS, LDAP credential disclosure, API RCE
- Default creds: `Admin:zabbix`
- Agent port: 10050, Server port: 10051

### Nagios (XI)
- Network monitoring
- Known for: RCE, SQLi, code injection
- Default creds: `nagiosadmin:PASSWD` (set during install)
- CVE-2021-25296: authenticated RCE via config wizards
- Metasploit: `exploit/linux/http/nagios_xi_configwizards_authenticated_rce`

### Oracle WebLogic
- 190+ CVEs
- Java Deserialization vulnerabilities
- T3 protocol attacks (port 7001)
- Common CVEs: CVE-2017-10271, CVE-2019-2725, CVE-2020-14882

### Wikis & Intranets
- **MediaWiki**: template injection, file upload
- **SharePoint**: deserialization, SSRF (CVE-2019-0604)
- Often contain sensitive internal documentation

### DotNetNuke (DNN)
- Authentication bypass
- XSS
- Arbitrary file upload
- Common in enterprise .NET environments

### VMware vCenter
- Apache Struts 2 RCE
- CVE-2021-22005: OVA file upload → RCE
- Post-exploit: JuicyPotato / PrintSpoofer privesc
- SAML token manipulation for admin access

---

## 4. Quick Assessment Checklist

When encountering any unknown application:
- [ ] Google: `"application name" default credentials`
- [ ] `searchsploit "application name"`
- [ ] Check Exploit-DB and CVE databases
- [ ] Look for admin panels on common paths (/admin, /administrator, /manage)
- [ ] Check for documentation pages leaking version info
- [ ] Test default credentials from vendor documentation
- [ ] Check if management interface is exposed to the network
