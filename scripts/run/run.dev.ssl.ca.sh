#!/usr/bin/env bash
# Description: Install Step CA Root CA ke OS, Firefox, Chrome/Chromium (Linux)
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Setup path & env ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a; . "$ENV_FILE"; set +a
fi

ROOT_CA_FILE="${ROOT_CA_FILE:-$ROOT_DIR/step-ca-public-root.pem}"
SAFE_APP_NAME="${APP_NAME:-app-boilerplate}"
SAFE_APP_NAME="${SAFE_APP_NAME// /-}"
SAFE_APP_NAME="${SAFE_APP_NAME,,}"
CERT_NICKNAME="${SAFE_APP_NAME}-step-ca"

ensure_sudo_session() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} This script needs sudo to install the Root CA into the OS trust store."
        exit 1
    fi

    echo -e "${YELLOW}[INFO]${NC} Administrator privilege is required to install the Root CA into the system trust store."
    sudo -v
}

echo -e "${CYAN}"
echo "=========================================================="
echo "   INSTALL STEP CA ROOT CERTIFICATE KE TRUST STORE"
echo "=========================================================="
echo -e "${NC}"

# Validasi file root CA tersedia
if [[ ! -f "$ROOT_CA_FILE" ]]; then
    echo -e "${RED}❌ File Root CA tidak ditemukan: $ROOT_CA_FILE${NC}"
    echo -e "${YELLOW}   Jalankan dulu: ./run.sh run.dev.ssl.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Root CA ditemukan: $ROOT_CA_FILE${NC}"
echo ""

# ============================================================
# 1. OS System Trust Store (Ubuntu/Debian/Arch)
# ============================================================
echo -e "${CYAN}[1/3] Menginstall ke System Trust Store (OS)...${NC}"

if command -v update-ca-certificates &>/dev/null; then
    # Ubuntu/Debian
    ensure_sudo_session
    sudo cp "$ROOT_CA_FILE" "/usr/local/share/ca-certificates/${CERT_NICKNAME}.crt"
    sudo update-ca-certificates
    echo -e "${GREEN}    ✓ Berhasil install ke Ubuntu/Debian trust store${NC}"

elif command -v update-ca-trust &>/dev/null; then
    # Fedora/RHEL/Arch
    ensure_sudo_session
    sudo cp "$ROOT_CA_FILE" "/etc/pki/ca-trust/source/anchors/${CERT_NICKNAME}.pem"
    sudo update-ca-trust extract
    echo -e "${GREEN}    ✓ Berhasil install ke Fedora/RHEL/Arch trust store${NC}"

else
    echo -e "${YELLOW}    ⚠️  Tidak dapat mendeteksi package manager untuk trust store.${NC}"
    echo -e "${YELLOW}       Copy manual: sudo cp $ROOT_CA_FILE /usr/local/share/ca-certificates/${CERT_NICKNAME}.crt${NC}"
fi

echo ""

# ============================================================
# 2. Firefox (NSS Database)
# ============================================================
echo -e "${CYAN}[2/3] Menginstall ke Firefox...${NC}"

if ! command -v certutil &>/dev/null; then
    echo -e "${YELLOW}    ⚠️  'certutil' tidak terinstall. Melewati Firefox.${NC}"
    echo -e "${YELLOW}       Install dengan: sudo apt install libnss3-tools${NC}"
else
    FIREFOX_PROFILES_FOUND=0

    for profile_dir in \
        "$HOME/.mozilla/firefox" \
        "$HOME/snap/firefox/common/.mozilla/firefox"
    do
        if [[ -d "$profile_dir" ]]; then
            for profile in "$profile_dir"/*.default* "$profile_dir"/*.default-release*; do
                if [[ -d "$profile" ]]; then
                    echo -e "    Memasang ke profil Firefox: $(basename "$profile")..."
                    # Hapus entry lama jika ada
                    certutil -D -d "sql:$profile" -n "$CERT_NICKNAME" 2>/dev/null || true
                    # Install baru
                    certutil -A -d "sql:$profile" -n "$CERT_NICKNAME" -t "CT,," -i "$ROOT_CA_FILE"
                    echo -e "${GREEN}    ✓ Berhasil: $(basename "$profile")${NC}"
                    FIREFOX_PROFILES_FOUND=$((FIREFOX_PROFILES_FOUND + 1))
                fi
            done
        fi
    done

    if [[ $FIREFOX_PROFILES_FOUND -eq 0 ]]; then
        echo -e "${YELLOW}    ⚠️  Tidak ada profil Firefox ditemukan. Pastikan Firefox pernah dibuka.${NC}"
    fi
fi

echo ""

# ============================================================
# 3. Chrome / Chromium (NSS Database)
# ============================================================
echo -e "${CYAN}[3/3] Menginstall ke Chrome / Chromium...${NC}"

if ! command -v certutil &>/dev/null; then
    echo -e "${YELLOW}    ⚠️  'certutil' tidak terinstall. Melewati Chrome/Chromium.${NC}"
    echo -e "${YELLOW}       Install dengan: sudo apt install libnss3-tools${NC}"
else
    CHROME_PROFILES_FOUND=0

    for chrome_dir in \
        "$HOME/.pki/nssdb" \
        "$HOME/.config/google-chrome/Default" \
        "$HOME/snap/chromium/current/.pki/nssdb"
    do
        if [[ -d "$chrome_dir" ]]; then
            echo -e "    Memasang ke profil Chrome/Chromium: $chrome_dir..."
            # Hapus entry lama jika ada
            certutil -D -d "sql:$chrome_dir" -n "$CERT_NICKNAME" 2>/dev/null || true
            # Install baru
            certutil -A -d "sql:$chrome_dir" -n "$CERT_NICKNAME" -t "CT,," -i "$ROOT_CA_FILE"
            echo -e "${GREEN}    ✓ Berhasil: $chrome_dir${NC}"
            CHROME_PROFILES_FOUND=$((CHROME_PROFILES_FOUND + 1))
        fi
    done

    # Global NSS DB (pki/nssdb) - buat jika belum ada
    mkdir -p "$HOME/.pki/nssdb"
    if ! certutil -L -d "sql:$HOME/.pki/nssdb" &>/dev/null; then
        certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password 2>/dev/null || true
    fi
    certutil -D -d "sql:$HOME/.pki/nssdb" -n "$CERT_NICKNAME" 2>/dev/null || true
    certutil -A -d "sql:$HOME/.pki/nssdb" -n "$CERT_NICKNAME" -t "CT,," -i "$ROOT_CA_FILE"
    echo -e "${GREEN}    ✓ Global NSS DB ($HOME/.pki/nssdb) berhasil diperbarui${NC}"
fi

echo ""
echo -e "${GREEN}=========================================================="
echo "✅ SELESAI! Root CA berhasil diinstall."
echo "=========================================================="
echo -e "${NC}"
echo -e "${YELLOW}⚠️  CATATAN PENTING:${NC}"
echo "   - Restart Firefox dan Chrome/Chromium agar perubahan berlaku."
echo "   - Jika browser sudah dibuka, tutup seluruhnya lalu buka kembali."
echo "   - Sertifikat ini untuk DEVELOPMENT saja, jangan digunakan di production."
echo ""
echo -e "   Root CA yang diinstall: ${CYAN}$ROOT_CA_FILE${NC}"
echo -e "   Nickname               : ${CYAN}$CERT_NICKNAME${NC}"
echo ""
