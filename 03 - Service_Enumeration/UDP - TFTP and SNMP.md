#  TFTP and SNMP


## 69 - TFTP

TFTP has no authentication. If it's open, you can read and write files.

```bash
sudo nmap -n -Pn -sU -oN tftp.txt -p 69 -sV --script tftp-enum $IP

# connect and grab files
tftp <target ip>
get /etc/passwd
put shell.php

# one liner
tftp <target ip> -c get /etc/passwd
```

## 161 - SNMP

SNMP can leak a massive amount of info: running processes, installed software, users, network interfaces, open ports, cron jobs. Always enumerate when open.

```bash
# identify the community string first (can use the seclists list)
onesixtyone -c /usr/share/seclists/Discovery/SNMP/snmp.txt <target ip>

# full walk with public community string
snmpwalk -v 2c -c public <IP>

# targeted OIDs for juicy info
snmpwalk -v 2c -c public <IP> 1.3.6.1.2.1.25.1.6.0        # system processes
snmpwalk -v 2c -c public <IP> 1.3.6.1.2.1.25.4.2.1.2       # running processes
snmpwalk -v 2c -c public <IP> 1.3.6.1.2.1.25.4.2.1.4       # processes with paths
snmpwalk -v 2c -c public <IP> 1.3.6.1.2.1.25.6.3.1.2       # installed software
snmpwalk -v 2c -c public <IP> 1.3.6.1.4.1.77.1.2.25        # user accounts (Windows)
snmpwalk -v 2c -c public <IP> 1.3.6.1.2.1.6.13.1.3         # TCP open ports

# extended MIBs (can reveal custom scripts, creds in command lines)
snmpwalk -v 2c -c public <IP> NET-SNMP-EXTEND-MIB::nsExtendOutputFull
snmpwalk -v 2c -c public <IP> NET-SNMP-EXTEND-MIB::nsExtendObjects

# if the above nsExtend commands do not produce readable output, try running
sudo apt-get install snmp-mibs-downloader

# snmpbulkwalk is faster for large walks
snmpbulkwalk -v 2c -c public <IP>
```

If you require to brute force the community string, you can also use hydra

```bash
hydra -P /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt <ip> snmp

# nmap brute
nmap -sU -p 161 --script snmp-brute <target ip>
```

SNMP can also reveal passwords in process command lines. Look for processes running with credentials as arguments (e.g. mysql -u root -pPassword123). Always check the full process list carefully.
