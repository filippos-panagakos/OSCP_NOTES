#!/bin/bash
# box-template.sh — Generate a writeup .md template for an HTB/OSCP box
# Usage: ./box-template.sh <box_name> [IP] [difficulty]

BOX="${1:?Usage: ./box-template.sh <box_name> [IP] [difficulty]}"
IP="${2:-10.10.10.X}"
DIFF="${3:-Medium}"
OUT="$(pwd)/${BOX,,}.md"

cat > "$OUT" << EOF
# $BOX — HTB $DIFF

## Recon

### TCP Scan
\`\`\`bash
nmap -sV -sC \$ip
\`\`\`
- Port X:

### UDP Scan
\`\`\`bash
sudo nmap -sU --top-ports 50 --min-rate 1000 \$ip
\`\`\`

### Web Enumeration
\`\`\`bash
gobuster dir -u http://\$ip -w /usr/share/wordlists/dirb/common.txt -x php,html,txt -t 50
\`\`\`

### Vhost Fuzzing
\`\`\`bash
ffuf -w /usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt -u http://${BOX,,}.htb -H "Host: FUZZ.${BOX,,}.htb" -ic -fw <baseline_words>
\`\`\`

## Foothold



## User Flag
\`\`\`
user.txt:
\`\`\`

## Privilege Escalation



## Root Flag
\`\`\`
root.txt:
\`\`\`

## Lessons Learned
-
EOF

echo "[+] Template created: $OUT"
