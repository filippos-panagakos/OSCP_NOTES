# DNS

Usually you only see this for DC machines, but always enumerate it when open.

## Nmap Scripts

```bash
nmap -sV -sC -p 53 <target ip>
nmap --script dns-* -p 53 <target ip>
```

## Basic Enumeration

```bash
nslookup <ip>

# reverse lookup
nslookup
> server <target ip>
> <target ip>

# or with dig
dig @<target ip> -x <target ip>

# find the domain name
dig @<target ip> any <domain>
```

## Zone Transfer

Even though AXFR is "out of scope" for OSCP, always try it. It dumps all DNS records including subdomains and internal hostnames.

```bash
dig axfr @<target ip> <domain>

# or
host -l <domain> <target ip>

# or with nmap
nmap --script dns-zone-transfer -p 53 --script-args dns-zone-transfer.domain=<domain> <target ip>
```

## Subdomain Enumeration

```bash
# brute force subdomains
gobuster dns -d <domain> -w /usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt -r <target ip>:53

# or with dnsenum
dnsenum --dnsserver <target ip> --enum -f /usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt <domain>
```

Always add discovered domains/subdomains to /etc/hosts:

```bash
echo "<target ip> <domain> <subdomain.domain>" | sudo tee -a /etc/hosts
```
