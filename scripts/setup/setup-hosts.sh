#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
HOSTS_FILE="/etc/hosts"
IP="127.0.0.1"
DRY_RUN=0

ONLY_TARGETS=""
INCLUDE_TARGETS=()
EXCLUDE_TARGETS=()

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --only=LIST          Target host yang akan di-setup (comma separated)
  --include=TARGET     Tambahkan target (boleh berulang)
  --exclude=LIST       Target yang di-skip (comma separated)
  --ip=IP              IP mapping di /etc/hosts (default: 127.0.0.1)
  --dry-run            Tampilkan rencana tanpa menulis file
  --help               Tampilkan bantuan

Target valid:
  app, cms, s3, s3-console, grafana, pma, hmr

Contoh:
  $0 --only=app,cms
  $0 --only=app,cms --exclude=pma
  $0 --include=s3 --include=s3-console --ip=10.10.10.20
EOF
}

for arg in "$@"; do
    case "$arg" in
        --only=*) ONLY_TARGETS="${arg#*=}" ;;
        --include=*) INCLUDE_TARGETS+=("${arg#*=}") ;;
        --exclude=*) EXCLUDE_TARGETS+=("${arg#*=}") ;;
        --ip=*) IP="${arg#*=}" ;;
        --dry-run) DRY_RUN=1 ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${YELLOW}[INFO]${NC} Running dry-run without sudo."
    else
        echo -e "${YELLOW}🔑 Membutuhkan hak akses Administrator. Masukkan password jika diminta:${NC}"
        exec sudo "$0" "$@"
    fi
fi

load_env_file() {
    local file="$1"
    if [ -f "$file" ]; then
        set -a
        source "$file"
        set +a
    else
        echo -e "${RED}[ERROR]${NC} File tidak ditemukan: $file"
        exit 1
    fi
}

extract_host() {
    local value="$1"
    local host="$value"

    host="${host#http://}"
    host="${host#https://}"
    host="${host%%/*}"
    host="${host%%:*}"
    echo "$host"
}

is_target_selected() {
    local target="$1"
    local item

    if [ -n "$ONLY_TARGETS" ]; then
        IFS=',' read -r -a arr <<< "$ONLY_TARGETS"
        local found=0
        for item in "${arr[@]}"; do
            [ "$item" = "$target" ] && found=1 && break
        done
        [ "$found" -eq 0 ] && return 1
    fi

    if [ ${#INCLUDE_TARGETS[@]} -gt 0 ]; then
        local found_include=0
        for item in "${INCLUDE_TARGETS[@]}"; do
            [ "$item" = "$target" ] && found_include=1 && break
        done
        if [ -z "$ONLY_TARGETS" ] && [ "$found_include" -eq 0 ]; then
            return 1
        fi
    fi

    if [ ${#EXCLUDE_TARGETS[@]} -gt 0 ]; then
        for item in "${EXCLUDE_TARGETS[@]}"; do
            IFS=',' read -r -a ex <<< "$item"
            local ex_item
            for ex_item in "${ex[@]}"; do
                [ "$ex_item" = "$target" ] && return 1
            done
        done
    fi

    return 0
}

append_host_entry() {
    local target="$1"
    local raw="$2"
    local host

    host="$(extract_host "$raw")"

    if [ -z "$host" ]; then
        echo -e "${YELLOW}[SKIP]${NC} [$target] value kosong, tidak ditambahkan."
        return
    fi

    if grep -qE "[[:space:]]${host}([[:space:]]|$)" "$HOSTS_FILE"; then
        echo -e "${YELLOW}[SKIP]${NC} [$target] '$host' sudah ada di $HOSTS_FILE."
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${GREEN}[PLAN]${NC} [$target] tambah: $IP $host"
        return
    fi

    echo "$IP $host" >> "$HOSTS_FILE"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[ADD]${NC} [$target] $IP $host"
    else
        echo -e "${RED}[FAIL]${NC} [$target] gagal menulis $host ke $HOSTS_FILE"
    fi
}

load_env_file "$ROOT_DIR/.env"
load_env_file "$ROOT_DIR/.env.devops"

declare -A HOST_SOURCES
HOST_SOURCES[app]="${APP_DOMAIN}"
HOST_SOURCES[cms]="${CMS_DOMAIN:-${CMS_URL}}"
HOST_SOURCES[s3]="${S3_DOMAIN:-${S3_URL}}"
HOST_SOURCES[s3-console]="${S3_CONSOLE_DOMAIN:-${S3_CONSOLE_URL}}"
HOST_SOURCES[grafana]="${GRAFANA_URL}"
HOST_SOURCES[pma]="${PMA_DOMAIN:-${PMA_ABSOLUTE_URI:-${PHPMYADMIN_URL}}}"
HOST_SOURCES[hmr]="${HMR_URL}"

VALID_TARGETS=(app cms s3 s3-console grafana pma hmr)

echo "🌐 Setup hosts entries (IP: $IP)"

for target in "${VALID_TARGETS[@]}"; do
    if is_target_selected "$target"; then
        append_host_entry "$target" "${HOST_SOURCES[$target]}"
    fi
done

echo -e "${GREEN}[DONE]${NC} setup-hosts selesai."
