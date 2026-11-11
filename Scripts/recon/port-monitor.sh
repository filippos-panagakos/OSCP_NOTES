#!/bin/bash
# port-monitor.sh — Watch for new ports opening on a target
# Usage: ./port-monitor.sh <IP> [interval_seconds]

IP="${1:?Usage: ./port-monitor.sh <IP> [interval_seconds]}"
INTERVAL="${2:-30}"
PREV="/tmp/ports-prev-$IP.txt"
CURR="/tmp/ports-curr-$IP.txt"

echo "[port-monitor] Watching $IP every ${INTERVAL}s — Ctrl+C to stop"

# Initial scan
nmap -p- --min-rate 3000 -T4 "$IP" 2>/dev/null | grep '^[0-9]' | cut -d'/' -f1 | sort -n > "$PREV"
echo "[+] Initial ports: $(cat "$PREV" | tr '\n' ',' | sed 's/,$//')"

while true; do
    sleep "$INTERVAL"
    nmap -p- --min-rate 3000 -T4 "$IP" 2>/dev/null | grep '^[0-9]' | cut -d'/' -f1 | sort -n > "$CURR"

    NEW=$(comm -13 "$PREV" "$CURR")
    CLOSED=$(comm -23 "$PREV" "$CURR")

    if [ -n "$NEW" ]; then
        echo "[!] $(date +%H:%M:%S) NEW PORTS: $(echo $NEW | tr '\n' ',' | sed 's/,$//')"
    fi
    if [ -n "$CLOSED" ]; then
        echo "[-] $(date +%H:%M:%S) CLOSED: $(echo $CLOSED | tr '\n' ',' | sed 's/,$//')"
    fi

    cp "$CURR" "$PREV"
done
