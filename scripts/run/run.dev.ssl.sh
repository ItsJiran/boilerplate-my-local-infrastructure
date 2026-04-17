#!/bin/bash

# =========================================================
# DEVELOPMENT SSL SETUP (STEP CA)
# =========================================================
# Mimics run.prod.ssl.sh behavior but uses local Step CA.
# Generates certificates for specified domains.
#
# Usage:
#   ./run.dev.ssl.sh --domain=app.test --domain=api.app.test
#   ./run.dev.ssl.sh --domains=app.test,api.app.test,s3.app.test
#
# =========================================================

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Variables Defaults ---
DOMAINS=()
OUTPUT_DIR="/etc/nginx/ssl"
EXPIRES="2160h" # Default 90 days

# Env variables for Step CA connection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

CA_PROVISIONER="${STEP_CA_PROVISIONER:-admin}"
CA_PASSWORD="${STEP_CA_PASSWORD:-changeme}" # Password for provisioner (be careful)
SUDO_REQUIRED=0

ensure_output_dir() {
    local dir="$1"
    local parent_dir

    if [ -d "$dir" ]; then
        if [ -w "$dir" ]; then
            return 0
        fi

        SUDO_REQUIRED=1
        return 0
    fi

    parent_dir="$(dirname "$dir")"
    while [ ! -d "$parent_dir" ] && [ "$parent_dir" != "/" ]; do
        parent_dir="$(dirname "$parent_dir")"
    done

    if [ -w "$parent_dir" ]; then
        mkdir -p "$dir"
        return 0
    fi

    SUDO_REQUIRED=1
}

ensure_sudo_session() {
    if [ "$SUDO_REQUIRED" -ne 1 ] || [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] sudo is required to write into: $OUTPUT_DIR${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[INFO] Administrator privilege is required to write certificates into $OUTPUT_DIR.${NC}"
    sudo -v
}

install_output_file() {
    local source_file="$1"
    local destination_file="$2"
    local mode="$3"

    if [ "$SUDO_REQUIRED" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
        sudo mkdir -p "$OUTPUT_DIR"
        sudo install -m "$mode" "$source_file" "$destination_file"
    else
        install -m "$mode" "$source_file" "$destination_file"
    fi
}

usage() {
        cat <<EOF
Usage: $0 [options]

Options:
    --domain=VALUE       Domain/URL manual (can be repeated)
    --domains=LIST       List of domains (comma separated)
    --output-dir=DIR     Directory to save certificates (default: /etc/nginx/ssl)
    --expires=DURATION   Certificate expiration duration (default: 2160h)
    --permanent          Set expiration to 100 years (~permanent)
    --help               Show help

Example:
    $0 --domains=app.test,api.app.test
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
        --domain=*) add_domain_unique "${1#*=}" ;;
        --domain) add_domain_unique "$2"; shift ;;
        --output-dir=*) OUTPUT_DIR="${1#*=}" ;;
        --expires=*) EXPIRES="${1#*=}" ;;
        --permanent) EXPIRES="876000h" ;; # 100 years
        --help)
            usage
            exit 0
            ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR] No domains provided.${NC}"
    usage
    exit 1
fi

ensure_output_dir "$OUTPUT_DIR"
ensure_sudo_session

CONTAINER_NAME="${APP_SLUG:-app}-step-ca"

# Verify container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo -e "${RED}[ERROR] Step CA container '${CONTAINER_NAME}' is not running.${NC}"
  echo "Please start the step-ca service first (e.g., ./run.sh run.step-ca.sh)"
  exit 1
fi

echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}       SSL CERTIFICATE GENERATION (STEP CA)              ${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo -e "Domains    : ${YELLOW}${DOMAINS[*]}${NC}"
echo -e "Output Dir : ${YELLOW}$OUTPUT_DIR${NC}"
echo -e "Container  : ${YELLOW}$CONTAINER_NAME${NC}"
echo ""

FAILED_DOMAINS=()
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

for DOMAIN in "${DOMAINS[@]}"; do
    echo -e "${BLUE}  → Generating for: $DOMAIN ...${NC}"
    
    # Generate inside container to avoid complex host setup
    # Using 'step ca certificate' command
    # We use a temporary path inside container
    TMP_CRT="/tmp/${DOMAIN}.crt"
    TMP_KEY="/tmp/${DOMAIN}.key"

    # Execute step command inside container
    # Note: We pass the password via stdin or --password-file
    # Creating a password file inside container temporarily
    
    docker exec "$CONTAINER_NAME" bash -c "echo '$CA_PASSWORD' > /tmp/pwd && step ca certificate '$DOMAIN' '$TMP_CRT' '$TMP_KEY' --provisioner='$CA_PROVISIONER' --password-file=/tmp/pwd --not-after='$EXPIRES' --force && rm /tmp/pwd" \
    || { FAILED_DOMAINS+=("$DOMAIN"); continue; }

    # Copy files out to host via a user-owned temp directory, then install them.
    LOCAL_CRT="$TMP_DIR/${DOMAIN}.crt"
    LOCAL_KEY="$TMP_DIR/${DOMAIN}.key"
    docker cp "$CONTAINER_NAME:$TMP_CRT" "$LOCAL_CRT"
    docker cp "$CONTAINER_NAME:$TMP_KEY" "$LOCAL_KEY"
    install_output_file "$LOCAL_CRT" "$OUTPUT_DIR/${DOMAIN}.crt" 644
    install_output_file "$LOCAL_KEY" "$OUTPUT_DIR/${DOMAIN}.key" 600
    
    # Cleanup inside
    docker exec "$CONTAINER_NAME" rm "$TMP_CRT" "$TMP_KEY"

    echo -e "${GREEN}    Done: $OUTPUT_DIR/${DOMAIN}.crt${NC}"
done

echo ""
if [ ${#FAILED_DOMAINS[@]} -eq 0 ]; then
    echo -e "${GREEN}SUCCESS! Certificates generated for all domains.${NC}"
else
    echo -e "${RED}FAILED for: ${FAILED_DOMAINS[*]}${NC}"
    exit 1
fi

# --- Download Root CA Certificate ---
echo ""
echo -e "${BLUE}Copying Root CA Certificate to project root...${NC}"

ROOT_CA_FILE="$ROOT_DIR/step-ca-public-root.pem"

ROOT_CA_CANDIDATES=(
    "/home/step/certs/root_ca.crt"
    "/etc/step-ca/certs/root_ca.crt"
)

ROOT_CA_COPIED=0
for cert_path in "${ROOT_CA_CANDIDATES[@]}"; do
    if docker exec "$CONTAINER_NAME" sh -lc "test -f '$cert_path'"; then
        docker cp "$CONTAINER_NAME:$cert_path" "$ROOT_CA_FILE"
        ROOT_CA_COPIED=1
        break
    fi
done

if [ "$ROOT_CA_COPIED" -eq 1 ] && grep -q "BEGIN CERTIFICATE" "$ROOT_CA_FILE"; then
    echo -e "${GREEN}✓ Root CA copied to: $ROOT_CA_FILE${NC}"
else
    # Last fallback: generate from CA home used by step-ca image.
    if docker exec "$CONTAINER_NAME" sh -lc "step certificate bundle /home/step/certs/intermediate_ca.crt /home/step/certs/root_ca.crt > /tmp/ca.pem" \
        && docker cp "$CONTAINER_NAME:/tmp/ca.pem" "$ROOT_CA_FILE" \
        && docker exec "$CONTAINER_NAME" rm -f /tmp/ca.pem \
        && grep -q "BEGIN CERTIFICATE" "$ROOT_CA_FILE"; then
        echo -e "${GREEN}✓ Root CA bundle created and copied to: $ROOT_CA_FILE${NC}"
    else
        echo -e "${RED}✗ Could not export Root CA certificate to: $ROOT_CA_FILE${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}✅ ALL DONE!${NC}"
echo -e "${YELLOW}Next: ./run.sh run.dev.ssl.ca.sh${NC}"
