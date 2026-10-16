# IIS Tilde Enumeration Methodology

## 1. Background

- Windows IIS uses 8.3 short file name format (legacy DOS naming)
- Files like `secret_document.txt` get short names like `SECRET~1.TXT`
- IIS responds differently to valid vs invalid short name prefixes
- Allows character-by-character enumeration of file/directory names

---

## 2. How It Works

- Send requests with `~` character followed by test characters
- HTTP 200 → character exists in a short file name at that position
- HTTP 404 → character does not exist
- Build up file names character by character (max 6 chars before `~1`)

### Example
```
http://TARGET/s~1 → 200 (file starting with 's' exists)
http://TARGET/se~1 → 200 (file starting with 'se' exists)
http://TARGET/sec~1 → 200 ...
http://TARGET/secr~1 → 200 ...
http://TARGET/secre~1 → 200 ...
http://TARGET/secret~1 → 200 (found: SECRET~1)
```

---

## 3. Automated Enumeration — shortscan

### Installation
```bash
go install github.com/bitquark/shortscan/cmd/shortscan@latest
```

### Usage
```bash
# Basic scan
shortscan http://TARGET/

# With custom wordlist for full name resolution
shortscan http://TARGET/ -w /usr/share/wordlists/seclists/Discovery/Web-Content/raft-small-words.txt

# Verbose output
shortscan -v http://TARGET/
```

### What It Does
1. Detects if tilde enumeration is possible
2. Enumerates short names character by character
3. Optionally resolves short names to full names using wordlist
4. Reports discovered files and directories

---

## 4. Alternative Tools

```bash
# IIS-ShortName-Scanner (Java)
java -jar iis_shortname_scanner.jar http://TARGET/

# tilde_enum (Python)
python3 tilde_enum.py -u http://TARGET/
```

---

## 5. What to Look For

| Short Name | Could Be |
|-----------|----------|
| BACKUP~1 | backup, backup.zip, backup.sql |
| CONFIG~1 | config.php, config.xml, configuration |
| PASSWO~1 | password.txt, passwords.xlsx |
| WEB~1.CON | web.config |
| DATABA~1 | database.sql, database.bak |
| GLOBAL~1 | global.asa, global.asax |

---

## 6. Post-Discovery

- [ ] Once short names found → use wordlist to guess full names
- [ ] Try accessing discovered files directly
- [ ] `web.config` — connection strings, credentials
- [ ] `.bak` files — source code backups
- [ ] `.sql` files — database dumps
- [ ] Hidden admin directories

---

## 7. Decision Tree

```
IIS Target
├── Tilde enumeration possible? (shortscan test)
│   ├── YES → Enumerate short names → resolve full names
│   │   ├── Config files? → web.config, connection strings
│   │   ├── Backup files? → source code disclosure
│   │   └── Hidden directories? → admin panels, upload dirs
│   └── NO → Standard directory brute force
```
