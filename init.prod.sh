#!/usr/bin/env bash

set -euo pipefail

# Production initialization workflow.
# Mirrors init.sh structure, but uses production env + docker-compose.prod.yml.

# ----------------------------------------------------------
# Step 1: Setup the production environment

if [ ! -f .env.fill ]; then
    cp .env.fill.example .env.fill
    echo "✅ Created .env.fill from example"
fi

./setup.sh setup-env-template.sh -o .env -t infra/env/templates/app.env -E .env.fill.example -E .env.fill -f
./setup.sh setup-env-template.sh -o .env.backend -t infra/env/templates/backend.env -E .env.fill.example -E .env.fill -f
./setup.sh setup-env-template.sh -o .env.devops -t infra/env/templates/devops.env -E .env.fill.example -E .env.fill -f

source ./.env
source ./.env.backend
source ./.env.devops

NGINX_TEMPLATE_ENV_ARGS=(
	-E .env
	-E .env.backend
	-E .env.devops
)

# Fallback jika APP_SLUG kosong/ketimpa oleh file env lain.
APP_SLUG_SAFE="${APP_SLUG:-}"
if [ -z "$APP_SLUG_SAFE" ]; then
	APP_SLUG_SAFE="$(printf '%s' "${APP_DOMAIN:-app}" | sed -E 's~^https?://~~; s~/.*$~~; s/\..*$//; s/[^A-Za-z0-9_-]+/-/g; s/^-+|-+$//g')"
fi
[ -z "$APP_SLUG_SAFE" ] && APP_SLUG_SAFE="app"

# ----------------------------------------------------------
# Step 2: Provision production SSL certificates (Let's Encrypt)

./run.sh run.prod.ssl.sh --domains="${APP_DOMAIN:-},${CMS_DOMAIN:-},${S3_DOMAIN:-},${S3_CONSOLE_DOMAIN:-},${PMA_DOMAIN:-}" --email="${CERTBOT_EMAIL:-admin@${APP_DOMAIN:-example.com}}"

# ----------------------------------------------------------
# Step 3: Build nginx host templates for VPS

HOST_FILE_NAME="${APP_DOMAIN:-app.example.com}"
SSL_CERT_PATH="${SSL_CERT_PATH:-/etc/letsencrypt/live/${HOST_FILE_NAME}/fullchain.pem}"
SSL_KEY_PATH="${SSL_KEY_PATH:-/etc/letsencrypt/live/${HOST_FILE_NAME}/privkey.pem}"

./setup.sh setup-nginx-template.sh -f \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/base.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/cms.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}" \
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/minio.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}" \
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/pma.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}" \
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/grafana.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	GRAFANA_PORT="${GRAFANA_PORT:-3000}" \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/reverb.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}" \
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/hmr.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="${SSL_CERT_PATH}" \
	SSL_KEY_PATH="${SSL_KEY_PATH}" \
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"

if grep -qE '^NGINX_HOST_FILE_NAME=' .env.devops; then
	sed -i "s|^NGINX_HOST_FILE_NAME=.*|NGINX_HOST_FILE_NAME=${HOST_FILE_NAME}|" .env.devops
else
	echo "NGINX_HOST_FILE_NAME=${HOST_FILE_NAME}" >> .env.devops
fi

# ----------------------------------------------------------
# Step 4: Build nginx LB templates for docker nginx

./setup.sh setup-nginx-template.sh -f \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/base.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	APP_PORT="${APP_PORT:-3000}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/cms.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/minio.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/pma.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/reverb.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	REVERB_SERVER_PORT="${REVERB_SERVER_PORT:-8080}"

# ----------------------------------------------------------
# Step 5: Deploy host nginx template into /etc/nginx

./setup.sh setup-nginx-file-to-host-conf.sh --file-name="${APP_DOMAIN:-app.example.com}"

# ----------------------------------------------------------
# Step 6: Deploy production application workflow

APP_PROD_SERVICES_BOOTSTRAP="mariadb redis db-init"
APP_PROD_SERVICES_RUNTIME="app app-worker app-socket app-cron load_balancer"
nextjs wordpress nginx
./run.sh run.app.sh up --file docker-compose.prod.yml --one-by-one $APP_PROD_SERVICES_BOOTSTRAP
./run.sh run.app.sh up --file docker-compose.prod.yml --one-by-one $APP_PROD_SERVICES_RUNTIME
