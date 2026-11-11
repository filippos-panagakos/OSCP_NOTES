#!/bin/bash
# crack.sh — Quick wrapper for hashcat/john with common modes
# Usage: ./crack.sh <hash_file> [mode] [wordlist]
# Examples:
#   ./crack.sh hash.txt ntlm
#   ./crack.sh hash.txt 5600 /path/to/wordlist.txt

HASHFILE="${1:?Usage: ./crack.sh <hash_file> [mode_name_or_number] [wordlist]}"
MODE="${2:-auto}"
WORDLIST="${3:-/usr/share/wordlists/rockyou.txt}"
RULES="/usr/share/hashcat/rules/best64.rule"

# Named mode shortcuts
declare -A MODES=(
    [md5]=0 [ntlm]=1000 [sha1]=100 [sha256]=1400 [sha512]=1700
    [bcrypt]=3200 [md5crypt]=500 [sha512crypt]=1800 [sha256crypt]=7400
    [mysql]=300 [mssql]=1731 [wordpress]=400 [phpass]=400
    [netntlmv2]=5600 [netntlmv1]=5500 [lm]=3000
    [ipmi]=7300 [kerberos]=13100 [asrep]=18200
    [wpa]=22000 [zip]=17200 [rar]=13000 [keepass]=13400
    [mscache2]=2100 [dpapi]=15300 [apache]=1600
)

if [ "$MODE" = "auto" ]; then
    echo "[*] No mode specified. Common modes:"
    for name in "${!MODES[@]}"; do
        printf "  %-15s → %s\n" "$name" "${MODES[$name]}"
    done | sort
    echo ""
    echo "Usage: ./crack.sh $HASHFILE <mode_name_or_number>"
    exit 0
fi

# Resolve named mode to number
if [[ "${MODES[$MODE]+exists}" ]]; then
    HASHCAT_MODE="${MODES[$MODE]}"
    echo "[+] Mode: $MODE → hashcat -m $HASHCAT_MODE"
else
    HASHCAT_MODE="$MODE"
    echo "[+] Mode: hashcat -m $HASHCAT_MODE"
fi

# Check if rockyou is extracted
if [ ! -f "$WORDLIST" ] && [ -f "${WORDLIST}.gz" ]; then
    echo "[*] Extracting ${WORDLIST}.gz..."
    sudo gunzip -k "${WORDLIST}.gz"
fi

echo "[*] Hash file: $HASHFILE"
echo "[*] Wordlist: $WORDLIST"
echo ""

# Try hashcat first
if command -v hashcat &>/dev/null; then
    echo "── hashcat (straight) ──"
    hashcat -m "$HASHCAT_MODE" "$HASHFILE" "$WORDLIST" --force -D 1 -O 2>/dev/null

    echo ""
    echo "── hashcat (with rules) ──"
    hashcat -m "$HASHCAT_MODE" "$HASHFILE" "$WORDLIST" -r "$RULES" --force -D 1 -O 2>/dev/null

    echo ""
    echo "── Results ──"
    hashcat -m "$HASHCAT_MODE" "$HASHFILE" --show 2>/dev/null
else
    echo "[!] hashcat not found, trying john..."
    john "$HASHFILE" --wordlist="$WORDLIST" 2>/dev/null
    john "$HASHFILE" --show 2>/dev/null
fi
