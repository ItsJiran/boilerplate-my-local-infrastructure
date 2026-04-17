#!/usr/bin/env bash

set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPLACE=0

ENV_FILES=(
  ".env"
  ".env.backend"
  ".env.devops"
)

TEMPLATES=(
  "prometheus.example.yml:prometheus.yml"
  "promtail.config.example.yml:promtail.config.yml"
)

show_help() {
  cat <<'EOF'
Usage: setup-monitoring-config.sh [OPTIONS]

Options:
  -r, --replace      Overwrite existing target files instead of skipping them.
  -h, --help         Show this help message and exit.
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -r|--replace)
        REPLACE=1
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        echo -e "${RED}[ERROR]${NC} Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

require_envsubst() {
  if ! command -v envsubst >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} envsubst (gettext) is required but not installed."
    echo -e "Install it (e.g. ${YELLOW}apt install gettext${NC}) or run this script in an environment where it is available."
    exit 1
  fi
}

verify_env_files() {
  local missing=0

  for env_file in "${ENV_FILES[@]}"; do
    if [ ! -f "$env_file" ]; then
      echo -e "${RED}[ERROR]${NC} Required environment file '$env_file' not found."
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

load_env_files() {
  set -a
  for env_file in "${ENV_FILES[@]}"; do
    # shellcheck disable=SC1090
    source "$env_file"
  done
  set +a
}

render_template() {
  local source_file="$1"
  local target_file="$2"

  if [ -d "$target_file" ]; then
    if [ -n "$(ls -A "$target_file" 2>/dev/null)" ]; then
      echo -e "${RED}[ERROR]${NC} Target '$target_file' is a non-empty directory."
      echo -e "${YELLOW}[HINT]${NC} Remove or rename the directory, then run again."
      exit 1
    fi
    rmdir "$target_file"
    echo -e "${YELLOW}[FIX]${NC} Removed empty directory at target path: $target_file"
  fi

  mkdir -p "$(dirname "$target_file")"

  if [ -f "$target_file" ]; then
    if [ "$REPLACE" -eq 0 ]; then
      echo -e "${YELLOW}[SKIP]${NC} $target_file sudah ada. Tidak ditimpa."
      return
    fi
    echo -e "${YELLOW}[REPLACE]${NC} $target_file akan ditimpa."
  fi

  if [ ! -f "$source_file" ]; then
    echo -e "${RED}[ERROR]${NC} File contoh $source_file tidak ditemukan."
    exit 1
  fi

  envsubst < "$source_file" > "$target_file"
  echo -e "${GREEN}[OK]${NC}   Dibuat $target_file dari $source_file"
}

parse_args "$@"

echo "🛠️  Menyiapkan konfigurasi monitoring (Prometheus + Promtail)..."
echo "----------------------------------------"

require_envsubst
verify_env_files
load_env_files

for template in "${TEMPLATES[@]}"; do
  IFS=":" read -r example target <<< "$template"
  render_template "$example" "$target"
done

echo "----------------------------------------"
echo -e "✅ Konfigurasi monitoring sudah tersedia. Silakan periksa ${YELLOW}prometheus.yml${NC} dan ${YELLOW}promtail.config.yml${NC}."
