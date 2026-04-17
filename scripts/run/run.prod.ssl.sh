#!/bin/bash

# =========================================================
# PRODUCTION SSL SETUP (LET'S ENCRYPT)
# =========================================================
# Automates the retrieval of SSL certificates using Certbot
# via Docker (Standalone Mode).
#
# Usage:
#   ./run.prod.ssl.sh --domain=jiran.com --domain=api.jiran.com --email admin@example.com
#   ./run.prod.ssl.sh --domains=jiran.com,api.jiran.com,reverb.jiran.com --email admin@example.com
# 
# Note: This script temporarily stops the 'load_balancer' service
# to allow Certbot to bind to port 80 for validation.
# =========================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Variables Defaults ---
DOMAINS=()
EMAIL=""
STAGING_FLAG="" # Set to "--test-cert" for staging/testing

usage() {
        cat <<EOF
Usage: $0 [options]

Options:
    --domain=VALUE       Domain/URL manual (boleh berulang)
    --domains=LIST       Daftar domain (comma separated)
    --email=VALUE        Email untuk registrasi Let's Encrypt
    --staging            Gunakan Let's Encrypt staging
    --help               Tampilkan bantuan

Contoh:
    $0 --domain=jiran.com --domain=api.jiran.com --email admin@jiran.com
    $0 --domains=jiran.com,api.jiran.com,reverb.jiran.com --email admin@jiran.com
EOF
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

add_domain_unique() {
        local candidate
        candidate="$(extract_host "$1")"
        [ -z "$candidate" ] && return

        local existing
        for existing in "${DOMAINS[@]}"; do
                [ "$existing" = "$candidate" ] && return
        done
        DOMAINS+=("$candidate")
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --domains=*)
            IFS=',' read -r -a domain_list <<< "${1#*=}"
            for item in "${domain_list[@]}"; do
                add_domain_unique "$item"
            done
            ;;
        --domain=*|--url=*) add_domain_unique "${1#*=}" ;;
        --domain|--url) add_domain_unique "$2"; shift ;;
        --email=*) EMAIL="${1#*=}" ;;
        --email) EMAIL="$2"; shift ;;
        --staging) STAGING_FLAG="--test-cert" ;;
        --help)
            usage
            exit 0
            ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Load Environment Variables (Backup) ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    source "$ROOT_DIR/.env"
    set +a
fi

if [ -f "$ROOT_DIR/.env.devops" ]; then
    set -a
    source "$ROOT_DIR/.env.devops"
    set +a
fi

# Default fallback: app domain only
if [ ${#DOMAINS[@]} -eq 0 ]; then
    add_domain_unique "${APP_DOMAIN}"
fi

PRIMARY_DOMAIN="${DOMAINS[0]}"
if [ -z "$EMAIL" ]; then
    EMAIL="${CERTBOT_EMAIL:-admin@${PRIMARY_DOMAIN}}"
fi

# --- Validation ---
if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR] Domain list is empty.${NC}"
    usage
    exit 1
fi

for DOMAIN in "${DOMAINS[@]}"; do
    if [ -z "$DOMAIN" ] || [[ "$DOMAIN" == "localhost" ]] || [[ "$DOMAIN" == *.test ]]; then
        echo -e "${RED}[ERROR] Invalid production domain: '$DOMAIN'${NC}"
        echo "Gunakan domain publik, atau jalankan untuk env local dengan setup SSL dev script."
        exit 1
    fi
done

if [ -z "$EMAIL" ]; then
    echo -e "${RED}[ERROR] Email is required for Let's Encrypt registration.${NC}"
    usage
    exit 1
fi

echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}       SSL CERTIFICATE AUTO-PROVISIONING (CERTBOT)       ${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo -e "Domains : ${YELLOW}${DOMAINS[*]}${NC}"
echo -e "Email   : ${YELLOW}$EMAIL${NC}"
echo -e "Mode    : ${YELLOW}Standalone per-domain (Docker)${NC}"
[ -n "$STAGING_FLAG" ] && echo -e "${YELLOW}(STAGING mode - certificates will NOT be trusted)${NC}"
echo ""

# --- 1. Stop Nginx (Port 80 Conflict) ---
echo -e "${YELLOW}[1/3] Stopping Nginx Load Balancer to free Port 80...${NC}"
docker compose stop nginx

# --- 2. Run Certbot per-domain ---
# Each domain gets its own cert at /etc/letsencrypt/live/<domain>/
# This makes nginx cert paths deterministic and independently renewable.
echo -e "${YELLOW}[2/3] Requesting certificates from Let's Encrypt (one per domain)...${NC}"

FAILED_DOMAINS=()
for DOMAIN in "${DOMAINS[@]}"; do
    echo -e "${BLUE}  → $DOMAIN${NC}"
    docker run --rm \
      -v "/etc/letsencrypt:/etc/letsencrypt" \
      -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
      -p 80:80 \
      certbot/certbot certonly --standalone \
        -d "$DOMAIN" \
      --email "$EMAIL" \
      --agree-tos \
      --no-eff-email \
      --non-interactive \
      $STAGING_FLAG \
    || FAILED_DOMAINS+=("$DOMAIN")
done

# --- 3. Restart Nginx ---
echo -e "${YELLOW}[3/3] Restarting Nginx Load Balancer...${NC}"
docker compose start nginx

# --- Result ---
if [ ${#FAILED_DOMAINS[@]} -eq 0 ]; then
    echo -e "${GREEN}SUCCESS! Certificates obtained for: ${DOMAINS[*]}${NC}"
    echo ""
    echo "Certificate paths:"
    for DOMAIN in "${DOMAINS[@]}"; do
        echo "  - /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    done
    echo ""
    echo "Update your nginx host config with:"
    echo "  setup-nginx-host.sh --app-domain=<domain> [--reverb-domain=<d> ...]"
else
    echo -e "${RED}FAILED for: ${FAILED_DOMAINS[*]}${NC}"
    echo "Check the error logs above."
    exit 1
fi
