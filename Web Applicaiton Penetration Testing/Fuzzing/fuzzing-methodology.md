# Fuzzing Methodology (ffuf & Feroxbuster)

---

## 1. ffuf — Core Syntax

```bash
ffuf -w <WORDLIST>:FUZZ -u <URL/FUZZ> [options]
```

### Essential Flags
| Flag | Purpose |
|------|---------|
| `-w wordlist:FUZZ` | Wordlist with keyword name |
| `-u URL` | Target URL (place `FUZZ` where you want to fuzz) |
| `-H "Header: FUZZ"` | Fuzz a header value |
| `-X POST` | HTTP method |
| `-d "param=FUZZ"` | POST body data |
| `-fc 403,404` | Filter by status code |
| `-fs 1234` | Filter by response size |
| `-fw 50` | Filter by word count |
| `-fl 20` | Filter by line count |
| `-ac` | Auto-calibrate filters (smart filtering) |
| `-ic` | Ignore comments in wordlist |
| `-mc 200,301` | Match only these status codes |
| `-t 50` | Threads (default 40) |
| `-r` | Follow redirects |
| `-o results.json` | Output to file |
| `-of csv` | Output format (json/csv/html) |
| `-e .php,.html` | Append extensions |
| `-recursion -recursion-depth 2` | Recursive fuzzing |
| `-v` | Verbose (show redirect location) |

---

## 2. Directory & File Fuzzing

### Basic Directory Fuzzing
```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt:FUZZ \
  -u http://TARGET/FUZZ -ic
```

### File Fuzzing with Extensions
```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt:FUZZ \
  -u http://TARGET/FUZZ -ic -e .php,.txt,.html,.bak,.old,.conf
```

### Extension Discovery (find what the server runs)
```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/web-extensions.txt:FUZZ \
  -u http://TARGET/indexFUZZ -ic -ac
```

### Common Wordlists
| Wordlist | Location |
|----------|----------|
| DirBuster Medium | `/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt` |
| DirBuster Small | `/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt` |
| Raft Large Dirs | `/usr/share/seclists/Discovery/Web-Content/raft-large-directories.txt` |
| Raft Large Files | `/usr/share/seclists/Discovery/Web-Content/raft-large-files.txt` |
| Common | `/usr/share/seclists/Discovery/Web-Content/common.txt` |
| Web Extensions | `/usr/share/seclists/Discovery/Web-Content/web-extensions.txt` |
| Subdomains Top 5k | `/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt` |
| Burp Params | `/usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt` |

---

## 3. Subdomain Enumeration

### Passive — subfinder
```bash
subfinder -d target.com -o subdomains.txt
```

### Active — ffuf DNS Fuzzing
```bash
ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt:FUZZ \
  -u http://FUZZ.target.com/ -ic
```
> Add discovered subdomains to `/etc/hosts` if needed

---

## 4. VHost Fuzzing

**Key concept**: VHosts are subdomains served on the same IP — they may not have public DNS records. You fuzz the `Host:` header instead of DNS.

```bash
ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt:FUZZ \
  -u http://target.com/ -H 'Host: FUZZ.target.com' -ic -fs <default_size>
```

### Steps:
- [ ] Run without `-fs` first to see the default response size
- [ ] Note the size of false positives (all same size = noise)
- [ ] Re-run with `-fs <that_size>` to filter them out
- [ ] Or use `-ac` for auto-calibration

### Add discovered VHosts to /etc/hosts
```bash
echo "TARGET_IP   admin.target.com archive.target.com" | sudo tee -a /etc/hosts
```

---

## 5. Parameter Fuzzing

### GET Parameter Discovery
```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt:FUZZ \
  -u http://TARGET/page.php?FUZZ=test -ic -ac
```

### POST Parameter Discovery
```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt:FUZZ \
  -u http://TARGET/page.php -X POST \
  -d 'FUZZ=test' -H 'Content-Type: application/x-www-form-urlencoded' \
  -ic -fs <error_size>
```

### Workflow:
- [ ] Try GET first
- [ ] No results? → switch to POST with `-X POST -d 'FUZZ=' -H 'Content-Type: ...'`
- [ ] Filter false positives with `-fs` (size of error responses)

---

## 6. Value Fuzzing

Once you find a parameter, fuzz its value:

```bash
# Numeric IDs
seq 1 1000 > ids.txt
ffuf -w ids.txt:FUZZ -u http://TARGET/admin.php -X POST \
  -d 'id=FUZZ' -H 'Content-Type: application/x-www-form-urlencoded' -fs <error_size>

# Usernames
ffuf -w /usr/share/seclists/Usernames/Names/names.txt:FUZZ \
  -u http://TARGET/page.php -X POST \
  -d 'username=FUZZ' -H 'Content-Type: application/x-www-form-urlencoded' -ac -ic

# Verify the hit
curl http://TARGET/page.php -X POST -d 'username=harry' \
  -H 'Content-Type: application/x-www-form-urlencoded'
```

---

## 7. Feroxbuster — Recursive Scanning

### Core Syntax
```bash
feroxbuster -u http://TARGET/ -w <WORDLIST> [options]
```

### Key Flags
| Flag | Purpose |
|------|---------|
| `-w WORDLIST` | Wordlist |
| `-x php,txt,bak` | Extensions to append |
| `-d N` / `--depth N` | Recursion depth (0 = infinite) |
| `-n` / `--no-recursion` | Flat scan only (no recursion) |
| `-t 50` | Threads |
| `-C 403,404` | Filter status codes |
| `-S 1234` | Filter by size |
| `-o results.txt` | Output file |
| `--burp` | Use Burp as proxy |
| `-r` | Follow redirects |
| `-k` | Ignore TLS errors |
| `-e` | Extract links from response bodies |

### Recursive Scan with Extensions
```bash
feroxbuster -u http://TARGET/ \
  -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt \
  -x php,phps,php7,txt,bak -d 3
```

### Flat Scan (no recursion)
```bash
feroxbuster -u http://TARGET/ \
  -w /usr/share/seclists/Discovery/Web-Content/common.txt -n
```

### ffuf vs Feroxbuster
| Feature | ffuf | Feroxbuster |
|---------|------|-------------|
| Recursion | Manual flag | Built-in by default |
| VHost fuzzing | Yes (`-H` flag) | No |
| Parameter fuzzing | Yes (FUZZ keyword) | No |
| Auto link extraction | No | Yes (`-e`) |
| Best for | Flexible fuzzing (headers, params, values) | Deep directory brute-force |

---

## 8. Full Assessment Walkthrough

### Phase 1: Subdomain / VHost Discovery
```bash
# Passive subdomain enum
subfinder -d target.com -o subs.txt

# Active VHost fuzzing
ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt:FUZZ \
  -u http://target.com/ -H 'Host: FUZZ.target.com' -ic -fs <default_size>

# Add discovered hosts
echo "TARGET_IP  sub1.target.com sub2.target.com" | sudo tee -a /etc/hosts
```

### Phase 2: Extension Scan (per VHost)
```bash
ffuf -w /usr/share/seclists/Discovery/Web-Content/web-extensions.txt:FUZZ \
  -u http://sub1.target.com/indexFUZZ -ic -ac
# Note found extensions: .php, .phps, .php7, etc.
```

### Phase 3: Directory & File Fuzzing
```bash
# Quick with ffuf
ffuf -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt:FUZZ \
  -u http://sub1.target.com/FUZZ -ic -e .php,.phps,.php7 -ac

# Deep with feroxbuster
feroxbuster -u http://sub1.target.com/ \
  -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt \
  -x php,phps,php7 -d 3
```

### Phase 4: Parameter Discovery
```bash
# GET first
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt:FUZZ \
  -u http://sub1.target.com/page.php7?FUZZ= -ic -ac

# No results → try POST
ffuf -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt:FUZZ \
  -u http://sub1.target.com/page.php7 -X POST \
  -d 'FUZZ=' -H 'Content-Type: application/x-www-form-urlencoded' -ic -fs <size>
```

### Phase 5: Value Fuzzing
```bash
# Fuzz the parameter value (e.g., username)
ffuf -w /usr/share/seclists/Usernames/Names/names.txt:FUZZ \
  -u http://sub1.target.com/page.php7 -X POST \
  -d 'username=FUZZ' -H 'Content-Type: application/x-www-form-urlencoded' -ac -ic
```

### Phase 6: Verify
```bash
curl http://sub1.target.com/page.php7 -X POST \
  -d 'username=harry' -H 'Content-Type: application/x-www-form-urlencoded'
```

---

## 9. Decision Tree

```
Target URL
├── Subdomain/VHost Discovery
│   ├── subfinder -d domain (passive)
│   └── ffuf -H 'Host: FUZZ.domain' (active, catches non-DNS vhosts)
│       └── Add all found to /etc/hosts
├── Per discovered host:
│   ├── Extension scan (web-extensions.txt on indexFUZZ)
│   ├── Directory fuzzing (with found extensions)
│   │   ├── Quick? → ffuf with -e
│   │   └── Deep? → feroxbuster with -x and --depth
│   ├── Found interesting page?
│   │   ├── GET parameter fuzz (?FUZZ=)
│   │   │   └── No hits? → POST parameter fuzz (-X POST -d 'FUZZ=')
│   │   └── Found parameter?
│   │       ├── Value fuzz (usernames, IDs, common values)
│   │       └── curl to verify and extract data
│   └── Check for backup files (.bak, .old, .swp, ~, .php.bak)
└── Repeat for each VHost/subdomain
```

---

## 10. Quick Reference — Filter Cheatsheet

```bash
# Filter by size (remove false positives of size 1234)
-fs 1234

# Filter by status code
-fc 403,404,500

# Filter by word count
-fw 50

# Filter by line count
-fl 20

# Match only specific codes
-mc 200,301,302

# Auto-calibrate (smart filtering)
-ac

# Combine: auto-calibrate + ignore comments
-ac -ic
```
