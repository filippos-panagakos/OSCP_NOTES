# Attacking Common Applications — OSCP Methodology Vault

> Source: HackTheBox Academy — Attacking Common Applications Module

## Structure

Each application has `notes/` (methodology) and `labs/` (walkthroughs) subfolders.

| Folder | Application | Key Attack |
|--------|-------------|------------|
| `wordpress/` | WordPress CMS | WPScan, Theme Editor RCE, Plugin Vulns |
| `joomla/` | Joomla CMS | Template Editor RCE, droopescan |
| `drupal/` | Drupal CMS | Drupalgeddon (1/2/3), PHP Filter, Backdoored Module |
| `tomcat/` | Apache Tomcat | WAR Upload, Manager Brute, CGI Injection |
| `jenkins/` | Jenkins CI/CD | Groovy Script Console, Freestyle Job RCE |
| `splunk/` | Splunk SIEM | Custom App Upload (inputs.conf → reverse shell) |
| `prtg/` | PRTG Network Monitor | Notification Command Injection |
| `osticket/` | osTicket | Email Pivoting to Internal Services |
| `gitlab/` | GitLab CE/EE | ExifTool RCE (CVE-2021-22205), Repo Secrets |
| `cgi-shellshock/` | CGI / Shellshock | CVE-2014-6271 via HTTP Headers |
| `coldfusion/` | Adobe ColdFusion | Dir Traversal, Pre-Auth RCE |
| `iis-tilde/` | IIS Tilde Enum | 8.3 Short Name Enumeration (shortscan) |
| `ldap/` | LDAP | Anonymous Bind, LDAP Injection |
| `thick-clients/` | Thick Client Apps | Decompile, Debug, Network Capture |
| `mass-assignment/` | Mass Assignment | Parameter Injection (admin=true) |
| `application-hardening/` | Hardening + Honorable Mentions | All apps + Nagios/WebLogic/Zabbix/etc. |
| `skills-assessments/` | Final Assessments | Tomcat CGI + Nagios XI Labs |
