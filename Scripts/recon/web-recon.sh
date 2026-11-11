#!/bin/bash
# web-recon.sh — Focused web enumeration (dirs, vhosts, tech detection)
# Usage: ./web-recon.sh <URL> [domain_for_vhosts]
# Example: ./web-recon.sh http://10.10.10.5 target.htb

URL="${1:?Usage: ./web-recon.sh <URL> [domain_for_vhosts]}"
DOMAIN="$2"
OUTDIR="$(pwd)/web-recon-$(date +%H%M%S)"
mkdir -p "$OUTDIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default wordlists
SMALL_WL="/usr/share/wordlists/dirb/common.txt"
BIG_WL="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"
VHOST_WL="/usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt"

echo -e "${CYAN}[web-recon] Target: $URL${NC}"
echo ""
echo -e "${YELLOW}[?] Use default wordlists or custom?${NC}"
echo -e "  1) Default (common.txt + medium + seclists vhosts)"
echo -e "  2) Custom — specify your own path(s)"
read -rp "  Choice [1]: " WL_CHOICE

if [ "$WL_CHOICE" = "2" ]; then
    read -rp "  Small/quick wordlist [$SMALL_WL]: " CUSTOM_SMALL
    [ -n "$CUSTOM_SMALL" ] && SMALL_WL="$CUSTOM_SMALL"

    read -rp "  Big/thorough wordlist [$BIG_WL]: " CUSTOM_BIG
    [ -n "$CUSTOM_BIG" ] && BIG_WL="$CUSTOM_BIG"

    if [ -n "$DOMAIN" ]; then
        read -rp "  Vhost wordlist [$VHOST_WL]: " CUSTOM_VHOST
        [ -n "$CUSTOM_VHOST" ] && VHOST_WL="$CUSTOM_VHOST"
    fi
fi

# Validate wordlists exist
for wl in "$SMALL_WL" "$BIG_WL"; do
    if [ ! -f "$wl" ]; then
        echo -e "${YELLOW}[!] Wordlist not found: $wl — skipping that scan${NC}"
    fi
done
echo ""

# Tech detection
echo -e "${YELLOW}[*] WhatWeb...${NC}"
whatweb "$URL" -a 3 > "$OUTDIR/whatweb.txt" 2>/dev/null
cat "$OUTDIR/whatweb.txt"

# Check for robots.txt & security.txt
echo -e "${YELLOW}[*] Checking robots.txt & security.txt...${NC}"
curl -sk "$URL/robots.txt" -o "$OUTDIR/robots.txt" 2>/dev/null
curl -sk "$URL/.well-known/security.txt" -o "$OUTDIR/security.txt" 2>/dev/null
[ -s "$OUTDIR/robots.txt" ] && echo -e "${GREEN}  [+] robots.txt found${NC}" && cat "$OUTDIR/robots.txt"

# Gobuster — common dirs
echo -e "${YELLOW}[*] Gobuster (common.txt + extensions)...${NC}"
[ -f "$SMALL_WL" ] && gobuster dir -u "$URL" -w "$SMALL_WL" -x php,html,txt,bak,asp,aspx -t 50 -q -o "$OUTDIR/gobuster-common.txt" 2>/dev/null

# Gobuster — big wordlist (background)
echo -e "${YELLOW}[*] Gobuster (big wordlist, background)...${NC}"
[ -f "$BIG_WL" ] && gobuster dir -u "$URL" -w "$BIG_WL" -t 50 -q -o "$OUTDIR/gobuster-medium.txt" 2>/dev/null &

# Nikto
echo -e "${YELLOW}[*] Nikto (background)...${NC}"
nikto -h "$URL" -o "$OUTDIR/nikto.txt" 2>/dev/null &

# Vhost fuzzing
if [ -n "$DOMAIN" ]; then
    echo -e "${YELLOW}[*] Vhost fuzzing on $DOMAIN...${NC}"
    # First get baseline word count
    BASELINE=$(curl -sk -H "Host: nonexistent12345.$DOMAIN" "$URL" | wc -w)
    echo -e "  Baseline word count: $BASELINE"
    ffuf -w "$VHOST_WL" \
        -u "$URL" -H "Host: FUZZ.$DOMAIN" -ic -fw "$BASELINE" \
        -o "$OUTDIR/vhosts.json" 2>/dev/null | tee "$OUTDIR/vhosts.txt"
fi

# Wait for background
echo -e "${YELLOW}[*] Waiting for background scans...${NC}"
wait

echo ""
echo -e "${GREEN}[+] Results in: $OUTDIR/${NC}"
echo -e "${CYAN}Quick look:${NC}"
echo "  cat $OUTDIR/gobuster-common.txt"
echo "  cat $OUTDIR/nikto.txt"
[ -n "$DOMAIN" ] && echo "  cat $OUTDIR/vhosts.txt"
