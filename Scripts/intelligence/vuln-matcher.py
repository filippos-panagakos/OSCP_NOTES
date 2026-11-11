#!/usr/bin/env python3
"""
vuln-matcher.py — Parse nmap XML output and search for known exploits
Usage: python3 vuln-matcher.py <nmap_scan.xml>

Parses service versions from nmap XML and searches searchsploit for each.
"""

import xml.etree.ElementTree as ET
import subprocess
import sys
import os

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN = '\033[0;36m'
NC = '\033[0m'

def parse_nmap_xml(xmlfile):
    """Extract services from nmap XML output"""
    services = []
    try:
        tree = ET.parse(xmlfile)
        root = tree.getroot()
        for host in root.findall('.//host'):
            ip = host.find('.//address[@addrtype="ipv4"]')
            ip_addr = ip.get('addr') if ip is not None else 'unknown'
            for port in host.findall('.//port'):
                portid = port.get('portid')
                protocol = port.get('protocol')
                state = port.find('state')
                if state is not None and state.get('state') != 'open':
                    continue
                service = port.find('service')
                if service is not None:
                    svc = {
                        'ip': ip_addr,
                        'port': portid,
                        'protocol': protocol,
                        'name': service.get('name', ''),
                        'product': service.get('product', ''),
                        'version': service.get('version', ''),
                        'extrainfo': service.get('extrainfo', ''),
                    }
                    services.append(svc)
    except ET.ParseError as e:
        print(f"{RED}[!] XML parse error: {e}{NC}")
        sys.exit(1)
    return services

def searchsploit(query):
    """Run searchsploit and return results"""
    try:
        result = subprocess.run(
            ['searchsploit', '--color', query],
            capture_output=True, text=True, timeout=15
        )
        lines = result.stdout.strip().split('\n')
        # Filter out header/footer lines
        exploits = [l for l in lines if '|' in l and 'Exploit Title' not in l and '---' not in l]
        return exploits
    except FileNotFoundError:
        return ["searchsploit not installed — sudo apt install exploitdb"]
    except:
        return []

def main():
    if len(sys.argv) < 2:
        print(f"Usage: python3 {sys.argv[0]} <nmap_scan.xml>")
        print(f"  Generate XML: nmap -sV -sC -oX scan.xml <target>")
        sys.exit(1)

    xmlfile = sys.argv[1]
    if not os.path.isfile(xmlfile):
        print(f"{RED}[!] File not found: {xmlfile}{NC}")
        sys.exit(1)

    services = parse_nmap_xml(xmlfile)
    if not services:
        print(f"{RED}[!] No open services found in {xmlfile}{NC}")
        sys.exit(1)

    print(f"{CYAN}╔══════════════════════════════════════╗{NC}")
    print(f"{CYAN}║       vuln-matcher.py                ║{NC}")
    print(f"{CYAN}╚══════════════════════════════════════╝{NC}")
    print(f"{YELLOW}[*] Parsed {len(services)} services from {xmlfile}{NC}")
    print()

    for svc in services:
        product = svc['product']
        version = svc['version']
        name = svc['name']

        display = f"{svc['port']}/{svc['protocol']} — {name}"
        if product:
            display += f" ({product} {version})"

        print(f"{CYAN}── {display} ──{NC}")

        # Build search queries — product+version first, then product alone
        queries = []
        if product and version:
            queries.append(f"{product} {version}")
        if product:
            queries.append(product)
        if not product and name:
            queries.append(name)

        found_any = False
        seen = set()
        for q in queries:
            results = searchsploit(q)
            for r in results:
                if r not in seen:
                    seen.add(r)
                    found_any = True
                    print(f"  {r}")

        if not found_any:
            print(f"  {YELLOW}No exploits found{NC}")
        print()

    print(f"{GREEN}[+] Done. To mirror an exploit:{NC}")
    print(f"  searchsploit -m <exploit_path>")

if __name__ == '__main__':
    main()
