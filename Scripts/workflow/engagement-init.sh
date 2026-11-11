#!/bin/bash
# engagement-init.sh — Create a structured folder for a new box/engagement
# Usage: ./engagement-init.sh <box_name> [IP]

if [ -z "$1" ]; then
    echo "Usage: ./engagement-init.sh <box_name> [IP]"
    exit 1
fi

BOX="$1"
IP="${2:-10.10.10.X}"
DIR="$(pwd)/$BOX"

mkdir -p "$DIR"/{nmap,web,exploits,loot,screenshots,notes}

cat > "$DIR/notes/README.md" << EOF
# $BOX

- **IP:** $IP
- **OS:**
- **Difficulty:**
- **Date Started:** $(date +%Y-%m-%d)

## Open Ports


## Foothold


## User Flag


## Privilege Escalation


## Root Flag


## Lessons Learned

EOF

cat > "$DIR/creds.txt" << EOF
# Credentials found for $BOX
# Format: service:username:password
EOF

# Add IP to /etc/hosts reminder
echo ""
echo "[+] Created: $DIR/"
echo "[+] Structure:"
find "$DIR" -type f -o -type d | sort | sed "s|$DIR/||" | head -20
echo ""
echo "[!] Don't forget: echo '$IP $BOX.htb' | sudo tee -a /etc/hosts"
