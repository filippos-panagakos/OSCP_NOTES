#!/usr/bin/env python3
"""
scope-osint.py — Passive recon on a domain (DNS, subdomains, tech stack)
Usage: python3 scope-osint.py <domain>
"""

import subprocess
import sys
import socket
import os

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN = '\033[0;36m'
NC = '\033[0m'

def run_cmd(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except:
        return ""

def main():
    domain = sys.argv[1] if len(sys.argv) > 1 else None
    if not domain:
        print(f"Usage: python3 {sys.argv[0]} <domain>")
        sys.exit(1)

    outdir = f"osint-{domain}"
    os.makedirs(outdir, exist_ok=True)

    print(f"{CYAN}╔══════════════════════════════════════╗{NC}")
    print(f"{CYAN}║         scope-osint.py               ║{NC}")
    print(f"{CYAN}╚══════════════════════════════════════╝{NC}")
    print(f"{YELLOW}[*] Target: {domain}{NC}")
    print()

    # DNS lookups
    print(f"{YELLOW}[*] DNS records{NC}")
    for rtype in ['A', 'AAAA', 'MX', 'NS', 'TXT', 'CNAME', 'SOA']:
        out = run_cmd(f"dig +short {domain} {rtype}")
        if out:
            print(f"  {GREEN}{rtype}: {out}{NC}")

    # Reverse DNS
    print(f"\n{YELLOW}[*] Reverse DNS{NC}")
    try:
        ip = socket.gethostbyname(domain)
        rev = run_cmd(f"dig +short -x {ip}")
        print(f"  {ip} → {rev or 'no PTR'}")
    except:
        print(f"  Could not resolve {domain}")

    # WHOIS summary
    print(f"\n{YELLOW}[*] WHOIS summary{NC}")
    whois = run_cmd(f"whois {domain} 2>/dev/null")
    for field in ['Registrar:', 'Creation Date:', 'Name Server:', 'Registrant Organization:']:
        for line in whois.split('\n'):
            if field.lower() in line.lower():
                print(f"  {line.strip()}")
                break
    with open(f"{outdir}/whois.txt", 'w') as f:
        f.write(whois)

    # Subdomain enum with dig zone transfer attempt
    print(f"\n{YELLOW}[*] Zone transfer attempt{NC}")
    ns_records = run_cmd(f"dig +short {domain} NS")
    for ns in ns_records.split('\n'):
        ns = ns.strip().rstrip('.')
        if ns:
            zt = run_cmd(f"dig @{ns} {domain} AXFR +short")
            if zt and 'Transfer failed' not in zt:
                print(f"  {RED}[!] Zone transfer SUCCESS on {ns}!{NC}")
                print(zt[:500])
                with open(f"{outdir}/zone-transfer.txt", 'w') as f:
                    f.write(zt)
            else:
                print(f"  {ns}: transfer denied (normal)")

    # Certificate transparency
    print(f"\n{YELLOW}[*] Certificate Transparency subdomains{NC}")
    ct_out = run_cmd(f"curl -sk 'https://crt.sh/?q=%25.{domain}&output=json' 2>/dev/null | python3 -c \"import sys,json; [print(e['name_value']) for e in json.load(sys.stdin)]\" 2>/dev/null | sort -u | head -30")
    if ct_out:
        subs = ct_out.split('\n')
        print(f"  {GREEN}Found {len(subs)} subdomains via crt.sh{NC}")
        for s in subs[:15]:
            print(f"    {s}")
        if len(subs) > 15:
            print(f"    ... and {len(subs)-15} more")
        with open(f"{outdir}/subdomains-ct.txt", 'w') as f:
            f.write(ct_out)
    else:
        print(f"  No results (or crt.sh unreachable)")

    # HTTP headers
    print(f"\n{YELLOW}[*] HTTP response headers{NC}")
    headers = run_cmd(f"curl -sIk https://{domain} 2>/dev/null | head -20")
    if not headers:
        headers = run_cmd(f"curl -sIk http://{domain} 2>/dev/null | head -20")
    if headers:
        for h in headers.split('\n'):
            h = h.strip()
            if any(x in h.lower() for x in ['server:', 'x-powered-by:', 'x-aspnet', 'x-generator']):
                print(f"  {RED}{h}{NC}")
            elif h:
                print(f"  {h}")
        with open(f"{outdir}/headers.txt", 'w') as f:
            f.write(headers)

    print(f"\n{GREEN}[+] Results saved to {outdir}/{NC}")

if __name__ == '__main__':
    main()
