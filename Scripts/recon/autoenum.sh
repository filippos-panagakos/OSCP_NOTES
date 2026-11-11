#!/bin/bash
# autoenum.sh — Full automated enumeration of a target
# Usage: ./autoenum.sh <IP> [output_dir]

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}Usage: ./autoenum.sh <IP> [output_dir]${NC}"
    exit 1
fi

IP="$1"
OUTDIR="${2:-$(pwd)/$IP}"
mkdir -p "$OUTDIR"/{nmap,web,smb,loot}

banner() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  autoenum — $1${NC}"
    echo -e "${CYAN}============================================${NC}"
}

# ─── Phase 1: Port Discovery ───
banner "Phase 1: TCP Port Discovery"
echo -e "${YELLOW}[*] Running quick TCP scan...${NC}"
nmap -p- --min-rate 3000 -T4 "$IP" -oN "$OUTDIR/nmap/all-tcp.txt" -oG "$OUTDIR/nmap/all-tcp.gnmap" 2>/dev/null

# Extract open ports
PORTS=$(grep -oP '\d+/open' "$OUTDIR/nmap/all-tcp.gnmap" 2>/dev/null | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')

if [ -z "$PORTS" ]; then
    echo -e "${RED}[!] No open TCP ports found. Check if host is up.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Open TCP ports: $PORTS${NC}"

# ─── Phase 2: Service Enumeration ───
banner "Phase 2: TCP Service Enumeration"
echo -e "${YELLOW}[*] Running service/version scan on open ports...${NC}"
nmap -p"$PORTS" -sV -sC -A "$IP" -oN "$OUTDIR/nmap/tcp-services.txt" -oX "$OUTDIR/nmap/tcp-services.xml" 2>/dev/null
echo -e "${GREEN}[+] TCP service scan complete${NC}"

# ─── Phase 3: UDP Top Ports ───
banner "Phase 3: UDP Top 50 Scan"
echo -e "${YELLOW}[*] Running UDP scan (top 50)...${NC}"
sudo nmap -sU --top-ports 50 --min-rate 1000 "$IP" -oN "$OUTDIR/nmap/udp-top50.txt" 2>/dev/null
echo -e "${GREEN}[+] UDP scan complete${NC}"

# ─── Phase 4: Vuln Scan ───
banner "Phase 4: Vulnerability Scan"
echo -e "${YELLOW}[*] Running vuln scripts on TCP ports...${NC}"
nmap -p"$PORTS" --script vuln "$IP" -oN "$OUTDIR/nmap/vuln-scan.txt" 2>/dev/null
echo -e "${GREEN}[+] Vuln scan complete${NC}"

# ─── Phase 5: Service-Specific Enumeration ───
banner "Phase 5: Service-Specific Enumeration"

# HTTP/HTTPS
for port in $(echo "$PORTS" | tr ',' '\n'); do
    if echo "$port" | grep -qE '^(80|443|8080|8443|8000|8888|3000|5000|9090)$'; then
        PROTO="http"
        [ "$port" = "443" ] || [ "$port" = "8443" ] && PROTO="https"
        URL="$PROTO://$IP:$port"

        echo -e "${YELLOW}[*] Web enumeration on port $port...${NC}"

        # whatweb
        whatweb "$URL" -a 3 > "$OUTDIR/web/whatweb-$port.txt" 2>/dev/null

        # gobuster directories
        if command -v gobuster &>/dev/null; then
            gobuster dir -u "$URL" -w /usr/share/wordlists/dirb/common.txt -x php,html,txt -t 50 -q -o "$OUTDIR/web/gobuster-$port.txt" 2>/dev/null &
        fi

        # nikto
        if command -v nikto &>/dev/null; then
            nikto -h "$URL" -o "$OUTDIR/web/nikto-$port.txt" 2>/dev/null &
        fi

        echo -e "${GREEN}[+] Web enum launched for port $port (background)${NC}"
    fi
done

# SMB (139/445)
if echo "$PORTS" | grep -qE '(^|,)(139|445)(,|$)'; then
    echo -e "${YELLOW}[*] SMB enumeration...${NC}"

    # Null session check
    smbclient -N -L "//$IP/" > "$OUTDIR/smb/smbclient-null.txt" 2>&1

    # enum4linux-ng
    if command -v enum4linux-ng &>/dev/null; then
        enum4linux-ng -A "$IP" -oJ "$OUTDIR/smb/enum4linux" 2>/dev/null &
    elif command -v enum4linux &>/dev/null; then
        enum4linux -a "$IP" > "$OUTDIR/smb/enum4linux.txt" 2>&1 &
    fi

    # netexec/crackmapexec
    if command -v netexec &>/dev/null; then
        netexec smb "$IP" -u '' -p '' --shares > "$OUTDIR/smb/nxc-null-shares.txt" 2>&1
        netexec smb "$IP" -u 'guest' -p '' --shares > "$OUTDIR/smb/nxc-guest-shares.txt" 2>&1
    fi

    echo -e "${GREEN}[+] SMB enum launched${NC}"
fi

# FTP (21)
if echo "$PORTS" | grep -qE '(^|,)21(,|$)'; then
    echo -e "${YELLOW}[*] FTP anonymous check...${NC}"
    echo -e "anonymous\nanonymous" | ftp -n "$IP" 21 > "$OUTDIR/nmap/ftp-anon.txt" 2>&1
    nmap -p21 --script ftp-anon,ftp-bounce,ftp-syst "$IP" -oN "$OUTDIR/nmap/ftp-scripts.txt" 2>/dev/null
    echo -e "${GREEN}[+] FTP check complete${NC}"
fi

# SNMP (UDP 161)
if grep -q '161/open' "$OUTDIR/nmap/udp-top50.txt" 2>/dev/null; then
    echo -e "${YELLOW}[*] SNMP enumeration...${NC}"
    if command -v snmpwalk &>/dev/null; then
        snmpwalk -v2c -c public "$IP" > "$OUTDIR/loot/snmpwalk.txt" 2>&1 &
    fi
    if command -v onesixtyone &>/dev/null; then
        onesixtyone "$IP" public private manager > "$OUTDIR/loot/onesixtyone.txt" 2>&1
    fi
    echo -e "${GREEN}[+] SNMP enum launched${NC}"
fi

# IPMI (UDP 623)
if grep -q '623/open' "$OUTDIR/nmap/udp-top50.txt" 2>/dev/null; then
    echo -e "${YELLOW}[*] IPMI detected on UDP 623!${NC}"
    nmap -p623 -sU --script ipmi-version "$IP" -oN "$OUTDIR/nmap/ipmi.txt" 2>/dev/null
    echo -e "${RED}[!] Try: msfconsole → use auxiliary/scanner/ipmi/ipmi_dumphashes${NC}"
fi

# Wait for background jobs
echo -e "${YELLOW}[*] Waiting for background scans to finish...${NC}"
wait

# ─── Summary ───
banner "Scan Complete"
echo -e "${GREEN}[+] All results saved to: $OUTDIR/${NC}"
echo -e "${GREEN}[+] Open TCP ports: $PORTS${NC}"
echo ""
echo -e "${CYAN}Quick review:${NC}"
echo -e "  cat $OUTDIR/nmap/tcp-services.txt"
echo -e "  cat $OUTDIR/nmap/udp-top50.txt"
echo -e "  ls $OUTDIR/web/"
echo -e "  ls $OUTDIR/smb/"
