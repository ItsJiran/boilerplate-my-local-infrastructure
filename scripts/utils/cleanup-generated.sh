#!/bin/bash
# Clean up generated configuration files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "🧹 Cleaning up generated configuration..."

rm -f "$ROOT_DIR/.env" "$ROOT_DIR/.env.backend" "$ROOT_DIR/.env.devops"
rm -f "$ROOT_DIR/infra/nginx/default.conf"
rm -f "$ROOT_DIR/infra/nginx/default.conf.vps.template"
rm -f "$ROOT_DIR/infra/nginx/default.conf.lb.template"

# Remove SSL/certificate artifacts generated in project root only.
find "$ROOT_DIR" -maxdepth 1 -type f \( \
	-name "*.crt" -o \
	-name "*.csr" -o \
	-name "*.key" -o \
	-name "*.pem" \
\) -delete

# Remove generated files in infra-generated folders
rm -rf "$ROOT_DIR/infra-generated/nginx/"*
rm -rf "$ROOT_DIR/infra-generated/ssl/"*

echo "✅ Cleaned up: .env*, infra/nginx/default.conf, related temp templates, infra-generated folders, and root generated cert/key files (*.crt, *.csr, *.key, *.pem)"
