#!/bin/bash

# =========================================================
# DEPLOYMENT SCRIPT (SERVER SIDE)
# =========================================================
# This script is executed by GitHub Actions via SSH.
# It updates the application code and Docker containers.
#
# Usage: ./deploy.sh [VERSION_TAG]
# Example: ./deploy.sh v1.0.0
# =========================================================

set -e  # Exit immediately if a command exits with a non-zero status.

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Arguments ---
VERSION_TAG=$1

if [ -z "$VERSION_TAG" ]; then
    echo -e "${RED}Error: Version tag is required.${NC}"
    echo "Usage: ./deploy.sh <version_tag>"
    exit 1
fi

echo -e "${GREEN}🚀 STARTING DEPLOYMENT: ${YELLOW}$VERSION_TAG${NC}"
echo "-------------------------------------------------------"

# 1. Update Codebase (Partial/Sparse - No Source Code)
echo -e "${YELLOW}[1/5] Updating configuration and scripts...${NC}"
# We assume the CI/CD pipeline has already transferred the necessary files (scripts/, docker-compose.prod.yml, config.json)
# via SCP/Rsync BEFORE running this script.
# Alternatively, if we use git, we fetch but don't pull app/
# For this "Enterprise" setup, we trust the files are present or updated via a separate step.
# If using git for scripts only:
# git fetch origin main
# git checkout origin/main -- scripts/ docker-compose.prod.yml config.json .env.example .env.example.backend .env.example.devops

# 2. Setup Environment Variables
echo -e "${YELLOW}[2/5] Setting up environment variables...${NC}"

# Pre-scan arguments for APP_ENV to determine which config to load
TARGET_ENV="production"
for arg in "$@"; do
  case $arg in
    --APP_ENV=*)
      TARGET_ENV="${arg#*=}"
      ;;
  esac
done

# A. Run setup-env.sh to generate base config from config.json
# We use --force to overwrite existing .env files with fresh config
./setup.sh setup-env.sh --env="$TARGET_ENV" --force

# B. Inject Dynamic Secrets (Arguments passed to deploy.sh)
echo "   -> Injecting secrets..."
# First, ensure DOCKER_IMAGE_TAG is set manually since we shifted $1
if [ -f ".env" ]; then
    if grep -q "^DOCKER_IMAGE_TAG=" .env; then
         sed -i "s|^DOCKER_IMAGE_TAG=.*|DOCKER_IMAGE_TAG=$VERSION_TAG|" .env
    else
         # Ensure newline before appending
         if [ -n "$(tail -c1 .env)" ]; then echo "" >> .env; fi
         echo "DOCKER_IMAGE_TAG=$VERSION_TAG" >> .env
    fi
fi
shift 1

# Iterate remaining arguments (KEY=VALUE) and inject into .env files
ENV_FILES=(".env" ".env.backend" ".env.devops")
if [ $# -gt 0 ]; then
    for arg in "$@"; do
        clean_arg="${arg#--}"
        if [[ "$clean_arg" == *"="* ]]; then
            KEY="${clean_arg%%=*}"
            VALUE="${clean_arg#*=}"
            # Escape value for sed (escape / and &)
            SAFE_VALUE=$(echo "$VALUE" | sed 's/[\/&]/\\&/g')
            
            for ENV_FILE in "${ENV_FILES[@]}"; do
                if [ -f "$ENV_FILE" ]; then
                    if grep -q "^${KEY}=" "$ENV_FILE"; then
                        sed -i "s|^${KEY}=.*|${KEY}=${SAFE_VALUE}|" "$ENV_FILE"
                    fi
                fi
            done
        fi
    done
fi
echo -e "${GREEN}[OK]${NC}   Secrets injected."

# 3. Pull Docker Images (Artifacts)
echo -e "${YELLOW}[3/5] Pulling Docker images...${NC}"
# Use the production compose file (renamed to docker-compose.yml on server)
docker compose pull

# 4. Restart Containers
echo -e "${YELLOW}[4/5] Restarting containers...${NC}"
docker compose up -d --remove-orphans

# 4.5 Setup Nginx & SSL
echo -e "${YELLOW}[4.5] Configuring Nginx & SSL...${NC}"

# Setup Host Nginx (Load Balancer)
chmod +x scripts/setup/setup-nginx-host.sh
# Check if sudo is needed (usually yes on production unless running as root)
if [ "$EUID" -ne 0 ]; then
  sudo ./setup.sh setup-nginx-host.sh
else
  ./setup.sh setup-nginx-host.sh
fi

# Run Production SSL Setup (Certbot)
chmod +x scripts/run/run.prod.ssl.sh
./run.sh run.prod.ssl.sh

echo -e "${GREEN}✅ Deployment Successful! Version $VERSION_TAG is live.${NC}"
exit 0


# 3. Pull New Images
echo -e "${YELLOW}[3/5] Pulling Docker images...${NC}"
docker compose pull app app-worker app-socket

# 4. Rolling Restart
echo -e "${YELLOW}[4/5] Restarting containers...${NC}"
docker compose up -d --remove-orphans

# 5. Post-Deployment Tasks
echo -e "${YELLOW}[5/5] Running post-deployment tasks...${NC}"
# Wait for DB to be ready? (Usually already ready in rolling update)

echo "   -> Optimization..."
docker compose exec -T app php artisan optimize:clear
docker compose exec -T app php artisan config:cache
docker compose exec -T app php artisan route:cache
docker compose exec -T app php artisan view:cache

echo "-------------------------------------------------------"
echo -e "${GREEN}✅ DEPLOYMENT SUCCESSFUL!${NC}"
