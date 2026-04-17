#!/bin/bash
# Description: Start Step CA (Certificate Authority) server

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
INFRA_DIR="$ROOT_DIR/infra"

# Banner
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║        Step CA - Certificate Authority Server        ║"
echo "║              (DEVELOPMENT ONLY)                       ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${YELLOW}⚠️  Note: This is for DEVELOPMENT only${NC}"
echo -e "${YELLOW}   Production uses Let's Encrypt for SSL certificates${NC}"
echo ""

# Check if .env exists
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo -e "${YELLOW}Please run setup scripts first to create .env file${NC}"
    exit 1
fi

# Load environment variables
echo -e "${BLUE}Loading environment variables...${NC}"
set -a
source "$ROOT_DIR/.env"
set +a

# Set default values if not in .env
export STEP_CA_PORT=${STEP_CA_PORT:-9000}
export STEP_CA_NAME=${STEP_CA_NAME:-"App Boilerplate CA"}
export STEP_CA_DNS=${STEP_CA_DNS:-"step-ca,localhost"}
export STEP_CA_PROVISIONER=${STEP_CA_PROVISIONER:-"admin"}
export STEP_CA_PASSWORD=${STEP_CA_PASSWORD:-"changeme"}
export STEP_CA_ADMIN=${STEP_CA_ADMIN:-"admin@jiran.test"}
export STEP_CA_ADDRESS=${STEP_CA_ADDRESS:-":9000"}

# Check if network exists
echo -e "${BLUE}Checking Docker network...${NC}"
if ! docker network inspect ${APP_NETWORK:-app_boilerplate_network} >/dev/null; then
    echo -e "${YELLOW}Creating ${APP_NETWORK:-app_boilerplate_network}...${NC}"
    docker network create ${APP_NETWORK:-app_boilerplate_network}
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Network created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create network${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Network already exists${NC}"
fi

# Create SSL directory if not exists
if [ ! -d "$INFRA_DIR/ssl" ]; then
    echo -e "${YELLOW}Creating SSL directory...${NC}"
    mkdir -p "$INFRA_DIR/ssl"
fi

# Display configuration
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Step CA Configuration:${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "  CA Name:        ${GREEN}$STEP_CA_NAME${NC}"
echo -e "  Port:           ${GREEN}$STEP_CA_PORT${NC}"
echo -e "  DNS Names:      ${GREEN}$STEP_CA_DNS${NC}"
echo -e "  Provisioner:    ${GREEN}$STEP_CA_PROVISIONER${NC}"
echo -e "  Admin:          ${GREEN}$STEP_CA_ADMIN${NC}"
echo -e "  CA Address:     ${GREEN}https://localhost:$STEP_CA_PORT${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# Warning about password
if [ "$STEP_CA_PASSWORD" = "changeme" ]; then
    echo -e "${YELLOW}⚠️  INFO: Using default password (OK for development)${NC}"
    echo ""
fi

# Skip confirmation if --yes or -y argument is provided
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
    echo -e "${GREEN}Running in non-interactive mode. Proceeding...${NC}"
else
    # Confirmation prompt
    echo -e -n "${YELLOW}Start Step CA server? [y/N]:${NC} "
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Cancelled.${NC}"
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}Starting Step CA server...${NC}"
echo ""

# Start Docker Compose
cd "$INFRA_DIR"
echo "$INFRA_DIR"
docker compose -f docker-compose.step-ca.yml up -d

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Step CA server started successfully!${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Access Information:${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "  CA URL:         ${GREEN}https://localhost:$STEP_CA_PORT${NC}"
    echo -e "  Health Check:   ${GREEN}https://localhost:$STEP_CA_PORT/health${NC}"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo -e "  View logs:      ${BLUE}docker logs -f step-ca${NC}"
    echo -e "  Stop server:    ${BLUE}cd $INFRA_DIR && docker compose -f docker-compose.step-ca.yml down${NC}"
    echo -e "  Restart:        ${BLUE}cd $INFRA_DIR && docker compose -f docker-compose.step-ca.yml restart${NC}"
    echo ""
    echo -e "${YELLOW}Initialize Step CLI (first time):${NC}"
    echo -e "  ${BLUE}step-cli ca bootstrap --ca-url https://localhost:$STEP_CA_PORT --fingerprint \$(docker exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Wait a bit and show status
    echo -e "${BLUE}Waiting for service to be ready...${NC}"
    sleep 5
    
    echo ""
    docker ps --filter "name=step-ca" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Failed to start Step CA server${NC}"
    echo -e "${YELLOW}Check logs with: docker logs step-ca${NC}"
    exit 1
fi
