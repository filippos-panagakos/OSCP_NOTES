HTB Forge

Target: 10.129.x.x
OS: Linux
Difficulty: Medium

Enumeration

Nmap showed port 80 (HTTP) and port 443 (HTTPS) open. Gobuster or vhost enumeration revealed admin.forge.htb as a subdomain.

Visiting http://admin.forge.htb directly returns "Only localhost is allowed!" meaning the admin panel is restricted to requests originating from the server itself.

The main site at forge.htb has an image upload feature with two options: upload a local file or upload from a URL.

SSRF (Server-Side Request Forgery)

The "Upload from URL" feature is the SSRF vector. The server fetches whatever URL you provide, so you can make it request internal resources on your behalf.

The app blacklists "admin.forge.htb" in the URL field, but the check is case-sensitive. Using uppercase bypasses it:

url=http://ADMIN.FORGE.HTB&remote=1

The server fetches the admin page from localhost (bypassing the "only localhost" restriction) and saves the response as an "uploaded image." Curling the resulting upload URL reveals the admin page HTML instead of an image:

curl http://forge.htb/uploads/RANDOMSTRING

Admin Panel Enumeration via SSRF

The admin panel has an /announcements page. Fetching it through SSRF:

url=http://ADMIN.FORGE.HTB/announcements&remote=1

Curling the upload link reveals:
1. Internal FTP credentials: user:heightofsecurity123!
2. The /upload endpoint supports ftp, ftps, http and https protocols
3. The /upload endpoint accepts a ?u= parameter for easy scripting

Chaining SSRF to FTP

Using the admin upload endpoint's ?u= parameter to access the internal FTP server:

url=http://ADMIN.FORGE.HTB/upload?u=ftp://user:heightofsecurity123!@LOCALHOST&remote=1

If "LOCALHOST" is blacklisted, try 127.0.0.1 or other variations.

This makes the server connect to its own FTP service with the discovered credentials, and the directory listing (or file contents) gets saved as the "uploaded image." Curl the upload URL to read the FTP contents.

From the FTP server, enumerate the user's home directory to find SSH keys or other sensitive files. Use the same SSRF chain to read specific files:

url=http://ADMIN.FORGE.HTB/upload?u=ftp://user:heightofsecurity123!@LOCALHOST/.ssh/id_rsa&remote=1

User Access

Use the exfiltrated SSH private key to log in:

chmod 600 id_rsa
ssh -i id_rsa user@forge.htb

Privilege Escalation

TODO: check sudo -l, SUID binaries, Python scripts with sudo

Key Lessons

1. SSRF lets you access internal services that are restricted to localhost by making the server request them on your behalf
2. Case-sensitive blacklist checks can be bypassed with uppercase: ADMIN.FORGE.HTB bypasses a check for admin.forge.htb
3. Chain SSRF through multiple layers: SSRF to admin panel, admin panel's upload to FTP, FTP to read sensitive files
4. "Upload from URL" features are classic SSRF vectors. Always test what protocols they support (http, ftp, file, gopher)
5. When an upload returns a link to the "uploaded file," always check the raw content with curl. The server may have saved HTML, directory listings, or file contents instead of an actual image
6. Internal FTP services often have weaker credentials than external-facing ones
7. SSRF blacklist bypasses: uppercase, 127.0.0.1 vs localhost, decimal IP (2130706433), IPv6 (::1), DNS rebinding
