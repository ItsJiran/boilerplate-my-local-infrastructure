#!/usr/bin/env bash
set -euo pipefail

# --- Setup path & env ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ File .env tidak ditemukan di $ENV_FILE" >&2
  exit 1
fi

set -a; . "$ENV_FILE"; set +a

if [[ -z "${APP_DOMAIN:-}" ]]; then
  echo '❌ APP_DOMAIN harus ada di .env' >&2
  exit 1
fi

# --- Konfigurasi ---
STEP_CA_PORT="${STEP_CA_PORT:-9000}"
CONTAINER_NAME="step-ca"
CA_URL="${STEP_CA_URL:-https://localhost:${STEP_CA_PORT}}"

SAFE_APP_NAME="${APP_NAME:-$APP_DOMAIN}"
SAFE_APP_NAME="${SAFE_APP_NAME// /-}"
SAFE_APP_NAME="${SAFE_APP_NAME,,}"

CERT_LOCAL="$ROOT_DIR/gen-${SAFE_APP_NAME}.crt"
KEY_LOCAL="$ROOT_DIR/gen-${SAFE_APP_NAME}.key"
ROOT_CA_FILE="$ROOT_DIR/step-ca-public-root.pem"

echo "=========================================================="
echo "          VERIFIKASI SSL CERTIFICATE LOKAL                "
echo "=========================================================="

echo "🔍 1. Mengecek ketersediaan file sertifikat..."
MISSING_FILES=0
for f in "$CERT_LOCAL" "$KEY_LOCAL"; do
  if [[ ! -f "$f" ]]; then
    echo "   ❌ File hilang: $f"
    MISSING_FILES=1
  else
    echo "   ✅ File ditemukan: $f"
  fi
done

if [[ $MISSING_FILES -eq 1 ]]; then
  echo "❌ Verifikasi dibatalkan. Generate sertifikat terlebih dahulu dengan run.dev.ssl.sh."
  exit 1
fi

echo ""
echo "🔍 2. Mengecek status Step CA Container..."
if ! docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
  echo "   ❌ Container '$CONTAINER_NAME' tidak berjalan."
  echo "      Anda masih bisa mengecek pasangan kunci (Kecuali verifikasi Root CA)."
else
  echo "   ✅ Container CA berjalan."
  
  echo ""
  echo "🔍 3. Mengunduh Root CA dari CA Container via HTTP..."
  rm -f "/tmp/verify-root.pem"
  if curl -s -k "${CA_URL}/roots.pem" > "/tmp/verify-root.pem"; then
    echo "   ✅ Berhasil mengunduh Root CA."
    
    echo ""
    echo "🔍 4. Memverifikasi Sertifikat Server terhadap Root CA Docker..."
    if docker run --rm -v "$ROOT_DIR:/workspace" -v "/tmp:/tmp" smallstep/step-cli \
       step certificate verify "/workspace/$(basename "$CERT_LOCAL")" --roots "/tmp/verify-root.pem" 2>/dev/null; then
       echo "   ✅ Sertifikat VALID ditandatangani oleh Step CA dari Container ini."
    else
       echo "   ❌ SKENARIO GAGAL! Sertifikat ini TIDAK dikenali (Tidak Valid) oleh CA Container ini."
    fi
  else
    echo "   ❌ Gagal mengunduh Root CA via API HTTP."
  fi
fi

echo ""
echo "🔍 5. Memverifikasi kecocokan Cryptographic Key (Private Key vs Server Certificate)..."
# Menggunakan Hash dari EKSTRAKSI PUBLIK KEY ECDSA/RSA guna pencocokan ECDSA cert karena openssl RSA modulus tak mempan di Elliptic Curve.
CERT_PUB_HASH=$(openssl x509 -pubkey -noout -in "$CERT_LOCAL" 2>/dev/null | openssl sha256 | awk '{print $2}')
KEY_PUB_HASH=$(openssl pkey -pubout -in "$KEY_LOCAL" 2>/dev/null | openssl sha256 | awk '{print $2}')

if [[ "$CERT_PUB_HASH" == "$KEY_PUB_HASH" && -n "$CERT_PUB_HASH" ]]; then
  echo "   ✅ Pasangan Kunci COCOK (Matching RSA/ECDSA PubKey Hash)."
else
  echo "   ❌ Pasangan Kunci TIDAK COCOK!"
  echo "      Hash CRT Pub: $CERT_PUB_HASH"
  echo "      Hash KEY Pub: $KEY_PUB_HASH"
fi

echo ""
echo "🔍 6. Rangkuman Isi Sertifikat (step-cli inspect):"
docker run --rm -v "$ROOT_DIR:/workspace" smallstep/step-cli \
  step certificate inspect "/workspace/$(basename "$CERT_LOCAL")" --short

echo ""
echo "✅ Proses verifikasi selesai dijalankan."
