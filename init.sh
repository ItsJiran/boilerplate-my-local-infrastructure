#!/usr/bin/env bash

set -euo pipefail

# This is a example of workflow deployment
# It will setup the environment and deploy the workflow
# This pattern allows you to separate the environment setup and workflow deployment, making 
# it easier to manage and maintain your workflows.

# This pattern also used in the deployment workflow, where we have a separate workflow for deploying the environment and another workflow for deploying the application. This allows us to deploy the environment once and then deploy 
# the application multiple times without having to worry about the environment setup each time.

# Of course, in production you need to manualy configure match with ur needs, but this is a 
# good starting point for understanding how to structure your workflows and separate concerns.
   
# Developed by github.com/itsjiran   

# ----------------------------------------------------------
# Step 1: Setup the environment

if [ ! -f .env.fill ]; then
    cp .env.fill.example .env.fill
    echo "✅ Created .env.fill from example"
fi

./setup.sh setup-env-template.sh -o .env -t infra/env/templates/infra-local.env -E ./.env.fill -f
# ./setup.sh setup-env-template.sh -o .env.devops -t infra/env/templates/monitoring.env -E ./.env.fill -f

source ./.env
# source ./.env.devops

NGINX_TEMPLATE_ENV_ARGS=(
	-E .env
	# -E .env.devops
)

# ----------------------------------------------------------
# Step 2: Run the step-ca workflow

./run.sh run.step-ca.sh

# ----------------------------------------------------------
# Step 3: Run the dns workflow to setup dns records for the application

source ./.env
# source ./.env.devops

NGINX_TEMPLATE_ENV_ARGS=(
	-E .env
	# -E .env.devops
)
./run.sh run.dev.ssl.sh --domains="${PHPMYADMIN_DOMAIN},${GRAFANA_DOMAIN},${S3_DOMAIN},${S3_CONSOLE_DOMAIN},${PORTAINER_DOMAIN}" --output-dir="./infra-generated/ssl"

sudo cp ./infra-generated/ssl/*.crt /etc/nginx/ssl/
sudo cp ./infra-generated/ssl/*.key /etc/nginx/ssl/

./run.sh run.dev.ssl.ca.sh

# ./run.sh run.dev.ssl.verify.sh (Skipped as run.dev.ssl.sh output verified)

# ----------------------------------------------------------
# Step 4: Buat template untuk nginx-host (vps) 

source ./.env
# source ./.env.devops

NGINX_TEMPLATE_ENV_ARGS=(
	-E .env
	# -E .env.devops
)

./setup.sh setup-nginx-template.sh -f \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/app.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	APP_DOMAIN="${PHPMYADMIN_DOMAIN}" \
	SSL_CERT_PATH="/etc/nginx/ssl/${PHPMYADMIN_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${PHPMYADMIN_DOMAIN}.key" \
	LOAD_BALANCER_PORT="${PHPMYADMIN_PORT}"

./setup.sh setup-nginx-template.sh -a \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/app.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	APP_DOMAIN="${GRAFANA_DOMAIN}" \
	SSL_CERT_PATH="/etc/nginx/ssl/${GRAFANA_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${GRAFANA_DOMAIN}.key" \
	LOAD_BALANCER_PORT="${GRAFANA_PORT}"

./setup.sh setup-nginx-template.sh -a \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/app.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	APP_DOMAIN="${S3_DOMAIN}" \
	SSL_CERT_PATH="/etc/nginx/ssl/${S3_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${S3_DOMAIN}.key" \
	LOAD_BALANCER_PORT="8888"

./setup.sh setup-nginx-template.sh -a \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/custom.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	PORT_HTTP="${S3_PORT}" \
	PORT_HTTPS="${S3_CONSOLE_PORT}" \
	APP_DOMAIN="${S3_DOMAIN}" \
	SSL_CERT_PATH="/etc/nginx/ssl/${S3_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${S3_DOMAIN}.key" \
	LOAD_BALANCER_PORT="8889"

./setup.sh setup-nginx-template.sh -a \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/app.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	APP_DOMAIN="${S3_CONSOLE_DOMAIN}" \
	SSL_CERT_PATH="/etc/nginx/ssl/${S3_CONSOLE_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${S3_CONSOLE_DOMAIN}.key" \
	LOAD_BALANCER_PORT="8889"

./setup.sh setup-nginx-template.sh -a \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/app.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	APP_DOMAIN="${PORTAINER_DOMAIN}" \
	SSL_CERT_PATH="/etc/nginx/ssl/${PORTAINER_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${PORTAINER_DOMAIN}.key" \
	LOAD_BALANCER_PORT="${PORTAINER_PORT}"

sudo cp "infra-generated/nginx/default.conf.vps.template" "/etc/nginx/sites-enabled/local-infra.conf"