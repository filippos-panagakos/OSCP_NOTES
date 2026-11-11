#!/bin/bash
# hash-id.sh — Identify hash type and suggest hashcat/john modes
# Usage: ./hash-id.sh <hash_or_file>

INPUT="${1:?Usage: ./hash-id.sh <hash_or_file>}"

if [ -f "$INPUT" ]; then
    HASH=$(head -1 "$INPUT")
else
    HASH="$INPUT"
fi

LEN=${#HASH}

echo "╔══════════════════════════════════════╗"
echo "║          hash-id.sh                  ║"
echo "╚══════════════════════════════════════╝"
echo "Hash: ${HASH:0:60}..."
echo "Length: $LEN chars"
echo ""

identify() {
    case "$LEN" in
        32)
            if echo "$HASH" | grep -qP '^[a-fA-F0-9]{32}$'; then
                echo "[+] MD5 (hashcat -m 0)"
                echo "[+] NTLM (hashcat -m 1000)"
                echo "[+] MD4 (hashcat -m 900)"
            fi
            ;;
        40)
            echo "[+] SHA-1 (hashcat -m 100)"
            ;;
        56)
            echo "[+] SHA-224 (hashcat -m 1300)"
            ;;
        64)
            echo "[+] SHA-256 (hashcat -m 1400)"
            echo "[+] HMAC-SHA256 if contains ':' (hashcat -m 1450)"
            ;;
        96)
            echo "[+] SHA-384 (hashcat -m 10800)"
            ;;
        128)
            echo "[+] SHA-512 (hashcat -m 1700)"
            ;;
    esac

    # Pattern-based detection
    if echo "$HASH" | grep -qP '^\$1\$'; then
        echo "[+] MD5crypt / md5(unix) (hashcat -m 500)"
    elif echo "$HASH" | grep -qP '^\$2[aby]?\$'; then
        echo "[+] bcrypt (hashcat -m 3200)"
    elif echo "$HASH" | grep -qP '^\$5\$'; then
        echo "[+] SHA-256crypt (hashcat -m 7400)"
    elif echo "$HASH" | grep -qP '^\$6\$'; then
        echo "[+] SHA-512crypt / sha512(unix) (hashcat -m 1800)"
    elif echo "$HASH" | grep -qP '^\$y\$'; then
        echo "[+] yescrypt (john --format=crypt)"
    elif echo "$HASH" | grep -qP '^\$apr1\$'; then
        echo "[+] Apache MD5 (hashcat -m 1600)"
    elif echo "$HASH" | grep -qP '^\$P\$|^\$H\$'; then
        echo "[+] phpBB3 / WordPress (hashcat -m 400)"
    elif echo "$HASH" | grep -qP '^[a-fA-F0-9]{32}:[a-fA-F0-9]+$'; then
        echo "[+] MD5 with salt (hashcat -m 10 or -m 20)"
    elif echo "$HASH" | grep -qP '^[a-f0-9]{16}$'; then
        echo "[+] MySQL 3.x (hashcat -m 200) or half-LM"
    elif echo "$HASH" | grep -qP '^\*[A-F0-9]{40}$'; then
        echo "[+] MySQL 4.1+ / SHA1(SHA1()) (hashcat -m 300)"
    elif echo "$HASH" | grep -qiP 'rakp'; then
        echo "[+] IPMI2 RAKP HMAC-SHA1 (hashcat -m 7300)"
    elif echo "$HASH" | grep -qP '^aad3b435'; then
        echo "[+] LM Hash (hashcat -m 3000) — likely empty/disabled"
    elif echo "$HASH" | grep -qP '^[a-fA-F0-9]{32}:[a-fA-F0-9]{32}$'; then
        echo "[+] NTLM:LM format — extract NTLM (hashcat -m 1000)"
    elif echo "$HASH" | grep -qP '.*:.*:.*:.*:.*:'; then
        echo "[+] NetNTLMv2 (hashcat -m 5600)"
    elif echo "$HASH" | grep -qP '.*:::.*'; then
        echo "[+] NetNTLMv1 (hashcat -m 5500)"
    fi
}

identify

echo ""
echo "── Quick crack commands ──"
echo "  hashcat -m <mode> hash.txt /usr/share/wordlists/rockyou.txt"
echo "  hashcat -m <mode> hash.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule"
echo "  john hash.txt --wordlist=/usr/share/wordlists/rockyou.txt"
echo ""
echo "── hashid (if installed) ──"
command -v hashid &>/dev/null && hashid "$HASH" 2>/dev/null | head -5
