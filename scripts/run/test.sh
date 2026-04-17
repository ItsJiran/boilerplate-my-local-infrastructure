#!/bin/bash

# =========================================================
# TEST ENTRYPOINT
# =========================================================
# Behavior:
# 1) If service "app" exists and is running, run Laravel tests.
# 2) Otherwise run stack integration checks for Next.js/WordPress.
# =========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if docker compose ps --services --filter "status=running" | grep -q '^app$'; then
	docker compose exec -it app php artisan test "$@"
else
	echo "[INFO] Service 'app' tidak berjalan. Menjalankan integration checks..."
	bash "$SCRIPT_DIR/test.services.sh"
fi

