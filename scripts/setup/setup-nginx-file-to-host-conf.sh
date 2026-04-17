#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

SOURCE_FILE="$ROOT_DIR/infra/nginx/default.conf.vps.template"
TARGET_DIR="/etc/nginx/sites-available"
SYMLINK_DIR="/etc/nginx/sites-enabled"
FILE_NAME=""
COPY_TO=""
DRY_RUN=0
SKIP_RELOAD=0
SKIP_SYMLINK=0
RAW_FILE_NAME=""

usage() {
  cat <<USAGE
Usage: $0 [options]

Copy an nginx .conf file into sites-available and create a symlink in sites-enabled.

Options:
  --source=PATH        Source nginx conf file (default: infra/nginx/default.conf.vps.template)
  --file-name=NAME     Destination filename (without/with .conf)
  --target-dir=PATH    Destination directory (default: /etc/nginx/sites-available)
  --symlink-dir=PATH   Enabled sites dir (default: /etc/nginx/sites-enabled)
  --copy-to=PATH       Extra copy path (optional)
  --skip-symlink       Do not create symlink in sites-enabled
  --skip-reload        Do not run nginx -t and reload
  --dry-run            Print actions only
  --help
USAGE
}

ensure_conf_name() {
  local name="$1"
  if [[ "$name" == *.conf ]]; then
    echo "$name"
  else
    echo "${name}.conf"
  fi
}

load_env() {
  local f="$1"
  if [ -f "$f" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
  fi
}

resolve_path() {
  local input="$1"

  if [[ "$input" = /* ]]; then
    printf '%s\n' "$input"
    return
  fi

  if [ -e "$input" ]; then
    printf '%s\n' "$input"
    return
  fi

  printf '%s\n' "$ROOT_DIR/$input"
}

ensure_root_or_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} This script needs root privileges, but 'sudo' is not available."
    echo -e "${YELLOW}[HINT]${NC} Run as root or install sudo first."
    exit 1
  fi

  echo -e "${YELLOW}[INFO]${NC} Administrator privilege is required. Please enter your sudo password."
  exec sudo -E "$0" "$@"
}

cleanup_legacy_site_name() {
  local raw_name="$1"
  local normalized_name="$2"

  if [ -z "$raw_name" ] || [ "$raw_name" = "$normalized_name" ]; then
    return
  fi

  local legacy_target_file="$TARGET_DIR/$raw_name"
  local legacy_symlink_file="$SYMLINK_DIR/$raw_name"

  if [ -e "$legacy_symlink_file" ] || [ -L "$legacy_symlink_file" ]; then
    rm -f "$legacy_symlink_file"
    echo -e "${YELLOW}[FIX]${NC} Removed legacy site entry: $legacy_symlink_file"
  fi

  if [ -e "$legacy_target_file" ] || [ -L "$legacy_target_file" ]; then
    rm -f "$legacy_target_file"
    echo -e "${YELLOW}[FIX]${NC} Removed legacy site file: $legacy_target_file"
  fi
}

for arg in "$@"; do
  case "$arg" in
    --source=*) SOURCE_FILE="${arg#*=}" ;;
    --file-name=*) FILE_NAME="${arg#*=}" ;;
    --target-dir=*) TARGET_DIR="${arg#*=}" ;;
    --symlink-dir=*) SYMLINK_DIR="${arg#*=}" ;;
    --copy-to=*) COPY_TO="${arg#*=}" ;;
    --skip-symlink) SKIP_SYMLINK=1 ;;
    --skip-reload) SKIP_RELOAD=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help) usage; exit 0 ;;
    *) echo -e "${RED}[ERROR]${NC} Unknown argument: $arg"; usage; exit 1 ;;
  esac
done

load_env "$ROOT_DIR/.env"
load_env "$ROOT_DIR/.env.backend"
load_env "$ROOT_DIR/.env.devops"

if [ -z "$FILE_NAME" ]; then
  FILE_NAME="${NGINX_HOST_FILE_NAME:-${APP_DOMAIN:-default}}"
fi

SOURCE_FILE="$(resolve_path "$SOURCE_FILE")"
RAW_FILE_NAME="$FILE_NAME"
FILE_NAME="$(ensure_conf_name "$FILE_NAME")"
TARGET_FILE="$TARGET_DIR/$FILE_NAME"
SYMLINK_FILE="$SYMLINK_DIR/$FILE_NAME"

if [ ! -f "$SOURCE_FILE" ]; then
  echo -e "${RED}[ERROR]${NC} Source nginx conf not found: $SOURCE_FILE"
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}[DRY-RUN]${NC} Source: $SOURCE_FILE"
  echo -e "${YELLOW}[DRY-RUN]${NC} Target: $TARGET_FILE"
  [ "$SKIP_SYMLINK" -eq 0 ] && echo -e "${YELLOW}[DRY-RUN]${NC} Symlink: $SYMLINK_FILE"
  if [ "$RAW_FILE_NAME" != "$FILE_NAME" ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Legacy cleanup: $TARGET_DIR/$RAW_FILE_NAME and $SYMLINK_DIR/$RAW_FILE_NAME"
  fi
  [ -n "$COPY_TO" ] && echo -e "${YELLOW}[DRY-RUN]${NC} Extra copy: $COPY_TO"
  [ "$SKIP_RELOAD" -eq 0 ] && echo -e "${YELLOW}[DRY-RUN]${NC} Would run: nginx -t && systemctl reload nginx"
  exit 0
fi

ensure_root_or_sudo "$@"

mkdir -p "$TARGET_DIR"
mkdir -p "$SYMLINK_DIR"
cleanup_legacy_site_name "$RAW_FILE_NAME" "$FILE_NAME"
cp "$SOURCE_FILE" "$TARGET_FILE"
chmod 644 "$TARGET_FILE"

if [ "$SKIP_SYMLINK" -eq 0 ]; then
  ln -sfn "$TARGET_FILE" "$SYMLINK_FILE"
fi

if [ -n "$COPY_TO" ]; then
  mkdir -p "$(dirname "$COPY_TO")"
  cp "$TARGET_FILE" "$COPY_TO"
fi

restorecon -Rv /etc/nginx/ 2>/dev/null || true

if [ "$SKIP_RELOAD" -eq 1 ]; then
  echo -e "${GREEN}[DONE]${NC} Host config deployed to $TARGET_FILE (reload skipped)."
  exit 0
fi

nginx -t
systemctl reload nginx
echo -e "${GREEN}[DONE]${NC} Host config deployed and nginx reloaded: $TARGET_FILE"