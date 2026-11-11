#!/bin/bash
# proxy-chain.sh — Quick chisel/ligolo/sshuttle proxy setup helper
# Usage: ./proxy-chain.sh <method> <target_ip> [pivot_port]

METHOD="${1:?Usage: ./proxy-chain.sh <chisel|sshuttle|ligolo|ssh> <target_ip> [port]}"
TARGET="${2:?Provide target IP}"
PORT="${3:-1080}"

TUN0=$(ip addr show tun0 2>/dev/null | grep -oP 'inet \K[\d.]+')
[ -z "$TUN0" ] && TUN0=$(ip addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+')

echo "╔══════════════════════════════════════╗"
echo "║       proxy-chain.sh                 ║"
echo "╚══════════════════════════════════════╝"
echo "Method: $METHOD | Target: $TARGET | Port: $PORT | Your IP: $TUN0"
echo ""

case "$METHOD" in
    chisel)
        echo "── Chisel SOCKS Proxy ──"
        echo ""
        echo "1. Start server (your machine):"
        echo "   chisel server --reverse --port 8000"
        echo ""
        echo "2. On target (upload chisel first):"
        echo "   ./chisel client $TUN0:8000 R:$PORT:socks"
        echo ""
        echo "3. Use the proxy:"
        echo "   proxychains nmap -sT $TARGET"
        echo "   curl --socks5 127.0.0.1:$PORT http://$TARGET"
        echo ""
        echo "4. Add to /etc/proxychains4.conf:"
        echo "   socks5 127.0.0.1 $PORT"
        ;;

    sshuttle)
        echo "── sshuttle (SSH-based VPN) ──"
        echo ""
        echo "Requires SSH access to pivot host."
        echo ""
        echo "1. Route all traffic through pivot:"
        echo "   sshuttle -r user@$TARGET 10.0.0.0/8"
        echo ""
        echo "2. Specific subnet only:"
        echo "   sshuttle -r user@$TARGET 172.16.0.0/16"
        echo ""
        echo "3. With key:"
        echo "   sshuttle -r user@$TARGET --ssh-cmd 'ssh -i id_rsa' 10.0.0.0/8"
        ;;

    ssh)
        echo "── SSH Port Forwarding ──"
        echo ""
        echo "Dynamic (SOCKS proxy):"
        echo "  ssh -D $PORT -N -f user@$TARGET"
        echo "  → proxychains nmap -sT <internal_target>"
        echo ""
        echo "Local forward (one port):"
        echo "  ssh -L 8080:<internal_ip>:80 user@$TARGET"
        echo "  → browse http://localhost:8080"
        echo ""
        echo "Remote forward (callback):"
        echo "  ssh -R 4444:127.0.0.1:4444 user@$TARGET"
        echo ""
        echo "Add to /etc/proxychains4.conf:"
        echo "  socks5 127.0.0.1 $PORT"
        ;;

    ligolo)
        echo "── Ligolo-ng Tunnel ──"
        echo ""
        echo "1. Start proxy (your machine):"
        echo "   sudo ip tuntap add user $(whoami) mode tun ligolo"
        echo "   sudo ip link set ligolo up"
        echo "   ./proxy -selfcert"
        echo ""
        echo "2. On target (upload agent):"
        echo "   ./agent -connect $TUN0:11601 -ignore-cert"
        echo ""
        echo "3. In ligolo console:"
        echo "   session        # select the agent"
        echo "   ifconfig       # see internal networks"
        echo "   start          # start tunnel"
        echo ""
        echo "4. Add route (your machine):"
        echo "   sudo ip route add 172.16.0.0/16 dev ligolo"
        echo ""
        echo "Then scan/access internal network directly — no proxychains needed."
        ;;

    *)
        echo "Unknown method: $METHOD"
        echo "Options: chisel, sshuttle, ssh, ligolo"
        exit 1
        ;;
esac
