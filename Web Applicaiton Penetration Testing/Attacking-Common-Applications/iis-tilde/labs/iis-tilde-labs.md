# IIS Tilde Enumeration Labs

> Cross-reference: [[iis-tilde-methodology]]

---

## Lab 1: Enumerate Hidden Files with shortscan

### Steps

- [ ] Install shortscan:
```bash
go install github.com/bitquark/shortscan/cmd/shortscan@latest
```
- [ ] Run scan:
```bash
shortscan http://TARGET/
```
- [ ] Note discovered short names
- [ ] Resolve to full names using wordlist:
```bash
shortscan http://TARGET/ -w /usr/share/wordlists/seclists/Discovery/Web-Content/raft-large-words.txt
```
- [ ] Access discovered files for flag or sensitive data
- [ ] Check for `web.config`, backup files, hidden directories
