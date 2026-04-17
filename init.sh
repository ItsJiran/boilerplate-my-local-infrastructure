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

./setup.sh setup-env-template.sh -o .env -t infra/env/templates/app-laravel.env -E ./.env.fill -f
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

./run.sh run.dev.ssl.sh --domains="${APP_DOMAIN},${REVERB_DOMAIN},${HMR_DOMAIN}" --output-dir="./infra-generated/ssl"

cp ./infra-generated/ssl/*.crt /etc/nginx/ssl/
cp ./infra-generated/ssl/*.key /etc/nginx/ssl/

./run.sh run.dev.ssl.ca.sh

# ./run.sh run.dev.ssl.verify.sh (Skipped as run.dev.ssl.sh output verified)

# ----------------------------------------------------------
# Step 4: Buat template untuk nginx-host (vps) 

./setup.sh setup-nginx-template.sh -f \
	-o infra-generated/nginx/default.conf.vps.template \
	-t infra/nginx/templates/vps/app.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
	-v \
	SSL_CERT_PATH="/etc/nginx/ssl/${REVERB_DOMAIN}.crt" \
	SSL_KEY_PATH="/etc/nginx/ssl/${REVERB_DOMAIN}.key" \
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"

if [ -n "${REVERB_URL:-}" ]; then
	./setup.sh setup-nginx-template.sh -a \
		-o infra-generated/nginx/default.conf.vps.template \
		-t infra/nginx/templates/vps/reverb.conf \
		"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
		-v \
		SSL_CERT_PATH="/etc/nginx/ssl/${REVERB_DOMAIN}.crt" \
		SSL_KEY_PATH="/etc/nginx/ssl/${REVERB_DOMAIN}.key" \
		LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"
fi

if [ -n "${HMR_URL:-}" ]; then
	./setup.sh setup-nginx-template.sh -a \
		-o infra-generated/nginx/default.conf.vps.template \
		-t infra/nginx/templates/vps/hmr.conf \
		"${NGINX_TEMPLATE_ENV_ARGS[@]}" \
		-v \
		SSL_CERT_PATH="/etc/nginx/ssl/${HMR_DOMAIN}.crt" \
		SSL_KEY_PATH="/etc/nginx/ssl/${HMR_DOMAIN}.key" \
		LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT:-80}"
fi

# ----------------------------------------------------------
# Step 5: Konfigurasi nginx untuk nginx-lb (docker) 

./setup.sh setup-nginx-template.sh -f \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/base.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}" \

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/reverb.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}"

./setup.sh setup-nginx-template.sh -a \
	-o infra/nginx/default.conf.lb.template \
	-t infra/nginx/templates/hmr.conf \
	"${NGINX_TEMPLATE_ENV_ARGS[@]}"

# ----------------------------------------------------------
# Step 6: Setup the host template into the etc nginx and also setup to the host file (for local development)

# ./setup.sh setup-hosts.sh
# ./setup.sh setup-nginx-file-to-host-conf.sh

# ----------------------------------------------------------
# Step 7: Deploy the application workflow

APP_SERVICES_BOOTSTRAP="redis"
APP_SERVICES_RUNTIME="app app-hmr app-worker app-socket app-cron load_balancer"

./run.sh run.app.sh up --build --one-by-one $APP_SERVICES_BOOTSTRAP
./run.sh run.app.sh up --build --one-by-one $APP_SERVICES_RUNTIME

echo "✅ Setup complete. Services are up and ready."


# ----------------------------------------------------------
# Step 8: Jalanin test untuk memastikan semuanya berjalan dengan baik (opsional)

./run.sh test.sh