#!/bin/bash

# =========================================================
# TEST CONNECTIONS & HEALTHCHECKS
# =========================================================

# --- Warna ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}        MENJALANKAN INTEGRATION & HEALTH TESTS           ${NC}"
echo -e "${CYAN}=========================================================${NC}"

# --- Load Environment ---
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    source "$ROOT_DIR/.env"
    set +a
else
    echo -e "${RED}[ERROR] File .env tidak ditemukan! Pastikan sudah install.${NC}"
    exit 1
fi

COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
if [ "${APP_ENV:-local}" = "production" ] && [ -f "${ROOT_DIR}/docker-compose.prod.yml" ]; then
    COMPOSE_FILE="${ROOT_DIR}/docker-compose.prod.yml"
fi

function print_result() {
    local status=$1
    local name=$2
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}  ✓ [OK]    ${name}${NC}"
    else
        echo -e "${RED}  ✗ [FAIL]  ${name}${NC}"
    fi
}

echo -e "\n${YELLOW}1. Host to External Services (via Nginx/Load Balancer)${NC}"

# Test Next.js
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" "https://${APP_DOMAIN}")
if [ "$HTTP_CODE" -eq 200 ]; then
   print_result 0 "Next.js Frontend (https://${APP_DOMAIN})"
else
   print_result 1 "Next.js Frontend (https://${APP_DOMAIN}) - Code: $HTTP_CODE"
fi

# Test CMS (WordPress)
HTTP_CODE=$(curl -s -k -L -o /dev/null -w "%{http_code}" "https://${CMS_DOMAIN}/wp-login.php")
if [ "$HTTP_CODE" -eq 200 ]; then
   print_result 0 "WordPress Admin (https://${CMS_DOMAIN}/wp-login.php)"
else
   print_result 1 "WordPress Admin (https://${CMS_DOMAIN}/wp-login.php) - Code: $HTTP_CODE"
fi

# Test MinIO
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" "https://${S3_CONSOLE_DOMAIN}/minio/health/live")
if [ "$HTTP_CODE" -eq 200 ]; then
   print_result 0 "MinIO Console Health (https://${S3_CONSOLE_DOMAIN})"
else
   print_result 1 "MinIO Console Health (https://${S3_CONSOLE_DOMAIN}) - Code: $HTTP_CODE"
fi

echo -e "\n${YELLOW}2. Internal Container Connections${NC}"

# Helper to exec in nextjs container
exec_nextjs() {
    docker compose -f "$COMPOSE_FILE" exec -T nextjs "$@"
}

# Helper to exec in wordpress container
exec_wp() {
    docker compose -f "$COMPOSE_FILE" exec -T wordpress "$@"
}

# START TESTS
if docker compose -f "$COMPOSE_FILE" ps | grep -q "nextjs"; then

    # Test Redis from Next.js
    if exec_nextjs nc -z redis 6379; then
        print_result 0 "Next.js -> Redis (Connectivity)"
    else
        print_result 1 "Next.js -> Redis (Connectivity)"
    fi

    # Test MariaDB from Next.js (if needed)
    if exec_nextjs nc -z mariadb 3306; then
        print_result 0 "Next.js -> MariaDB (Connectivity)"
    else
        print_result 1 "Next.js -> MariaDB (Connectivity)"
    fi
else
    echo -e "${RED}[SKIP] Container Next.js tidak berjalan.${NC}"
fi

if docker compose -f "$COMPOSE_FILE" ps | grep -q "wordpress"; then
    # Test MariaDB from WordPress
    if exec_wp nc -z mariadb 3306; then
        print_result 0 "WordPress -> MariaDB (Connectivity)"
    else
        print_result 1 "WordPress -> MariaDB (Connectivity)"
    fi

    # Test Redis from WordPress
    if exec_wp nc -z redis 6379; then
        print_result 0 "WordPress -> Redis (Connectivity)"
    else
         print_result 1 "WordPress -> Redis (Connectivity)"
    fi
else
    echo -e "${RED}[SKIP] Container WordPress tidak berjalan.${NC}"
fi

echo -e "\n${CYAN}=========================================================${NC}"
echo -e "${GREEN}Test selesai.${NC}"
