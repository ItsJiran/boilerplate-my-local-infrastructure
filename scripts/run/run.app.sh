#!/bin/bash

# =========================================================
# CITRA KULINER - DOCKER COMPOSE MANAGER (STACK VERSION)
# =========================================================

# --- Konfigurasi Warna ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Load APP_SLUG dari .env ---
DEFAULT_APP_SLUG="app-boilerplate"
if [ -f .env ]; then
    ENV_SLUG=$(grep -E '^APP_SLUG=' .env | cut -d '=' -f 2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | tr -d '\r')
    [ -n "$ENV_SLUG" ] && DEFAULT_APP_SLUG="$ENV_SLUG"
elif [ -f .env.example ]; then
    ENV_SLUG=$(grep -E '^APP_SLUG=' .env.example | cut -d '=' -f 2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | tr -d '\r')
    [ -n "$ENV_SLUG" ] && DEFAULT_APP_SLUG="$ENV_SLUG"
fi

# --- Konfigurasi Target File & Stack (Namespace) ---
DEFAULT_FILE="docker-compose.yml"
DEFAULT_STACK="$DEFAULT_APP_SLUG" 

# --- Fungsi Load Environment ---
load_envs() {
    set -a
    [ -f .env ] && source .env
    [ -f .env.backend ] && source .env.backend
    [ -f .env.devops ] && source .env.devops
    set +a
}

ensure_app_network() {
    local network_name="${APP_NETWORK:-app_network}"

    if docker network inspect "$network_name" >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${YELLOW}[INFO]${NC} Network '$network_name' belum ada. Membuat network..."
    docker network create "$network_name" >/dev/null
    echo -e "${GREEN}[OK]${NC} Network '$network_name' siap digunakan."
}

load_services_from_compose() {
    # Cara utama: gunakan parser resmi docker compose
    mapfile -t SERVICES < <(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null)

    if [ "${#SERVICES[@]}" -gt 0 ]; then
        return 0
    fi

    # Fallback: parse langsung dari blok `services:` jika interpolasi env gagal
    mapfile -t SERVICES < <(
        awk '
            /^services:[[:space:]]*$/ { in_services=1; next }
            in_services && /^[^[:space:]]/ { in_services=0 }
            in_services && /^  [a-zA-Z0-9_.-]+:[[:space:]]*$/ {
                svc=$0
                sub(/^[[:space:]]+/, "", svc)
                sub(/:[[:space:]]*$/, "", svc)
                print svc
            }
        ' "$COMPOSE_FILE"
    )

    if [ "${#SERVICES[@]}" -eq 0 ]; then
        echo -e "${RED}[ERROR] Gagal membaca service dari '$COMPOSE_FILE'.${NC}"
        exit 1
    fi
}

append_services_from_csv() {
    local csv="$1"
    local parsed=()
    IFS=',' read -r -a parsed <<< "$csv"
    for svc in "${parsed[@]}"; do
        svc="${svc//[[:space:]]/}"
        [ -n "$svc" ] && NON_INTERACTIVE_SERVICES+=("$svc")
    done
}

run_up_non_interactive() {
    ensure_app_network

    if [ "${#NON_INTERACTIVE_SERVICES[@]}" -eq 0 ]; then
        echo -e "${GREEN}[EXEC] Starting all services (Non-Interactive)...${NC}"
        docker compose -f "$COMPOSE_FILE" up -d "${NON_INTERACTIVE_FLAGS[@]}"
        return
    fi

    if [ "$NON_INTERACTIVE_ONE_BY_ONE" -eq 1 ]; then
        echo -e "${GREEN}[EXEC] Starting services one-by-one (Non-Interactive)...${NC}"
        for svc in "${NON_INTERACTIVE_SERVICES[@]}"; do
            echo -e "${CYAN}  -> up ${svc}${NC}"
            docker compose -f "$COMPOSE_FILE" up -d "${NON_INTERACTIVE_FLAGS[@]}" "$svc"
        done
        return
    fi

    echo -e "${GREEN}[EXEC] Starting selected services (Non-Interactive)...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d "${NON_INTERACTIVE_FLAGS[@]}" "${NON_INTERACTIVE_SERVICES[@]}"
}

# --- Non-Interactive Mode (CI/Scripting) ---
if [[ -n "$1" ]]; then
    COMPOSE_FILE="$DEFAULT_FILE"
    STACK_NAME="$DEFAULT_STACK"
    export COMPOSE_PROJECT_NAME="$STACK_NAME"
    
    ACTION="$1"
    shift

    NON_INTERACTIVE_ONE_BY_ONE=0
    NON_INTERACTIVE_FLAGS=()
    NON_INTERACTIVE_SERVICES=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file=*)
                COMPOSE_FILE="${1#--file=}"
                ;;
            --file)
                shift
                [ -z "$1" ] && {
                    echo "Missing value for --file"
                    exit 1
                }
                COMPOSE_FILE="$1"
                ;;
            --one-by-one)
                NON_INTERACTIVE_ONE_BY_ONE=1
                ;;
            --services=*)
                append_services_from_csv "${1#--services=}"
                ;;
            --services)
                shift
                [ -z "$1" ] && {
                    echo "Missing value for --services"
                    exit 1
                }
                append_services_from_csv "$1"
                ;;
            --*)
                NON_INTERACTIVE_FLAGS+=("$1")
                ;;
            *)
                NON_INTERACTIVE_SERVICES+=("$1")
                ;;
        esac
        shift
    done
    
    case "$ACTION" in
        up)
            load_envs
            if [ ! -f "$COMPOSE_FILE" ]; then
                echo -e "${RED}[ERROR] Compose file '$COMPOSE_FILE' tidak ditemukan!${NC}"
                exit 1
            fi
            run_up_non_interactive
            ;;
        down)
            if [ ! -f "$COMPOSE_FILE" ]; then
                echo -e "${RED}[ERROR] Compose file '$COMPOSE_FILE' tidak ditemukan!${NC}"
                exit 1
            fi
            if [ "${#NON_INTERACTIVE_SERVICES[@]}" -gt 0 ]; then
                echo -e "${RED}[EXEC] Stopping selected services...${NC}"
                docker compose -f "$COMPOSE_FILE" stop "${NON_INTERACTIVE_SERVICES[@]}"
            else
                echo -e "${RED}[EXEC] Stopping all services...${NC}"
                docker compose -f "$COMPOSE_FILE" down
            fi
            ;;
        *)
            echo "Unknown command: $ACTION"
            echo "Usage: $0 up [--file docker-compose.prod.yml] [--build] [--one-by-one] [--services=svc1,svc2 | svc1 svc2]"
            echo "       $0 down [--file docker-compose.prod.yml] [--services=svc1,svc2 | svc1 svc2]"
            exit 1
            ;;
    esac
    exit 0
fi

echo -e "${YELLOW}--- Konfigurasi Project ---${NC}"
read -p "Masukkan nama file (Default: $DEFAULT_FILE): " INPUT_FILE
COMPOSE_FILE=${INPUT_FILE:-$DEFAULT_FILE}

read -p "Masukkan nama Stack/Project (Default: $DEFAULT_STACK): " INPUT_STACK
STACK_NAME=${INPUT_STACK:-$DEFAULT_STACK}

export COMPOSE_PROJECT_NAME=$STACK_NAME

if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}[ERROR] File '$COMPOSE_FILE' tidak ditemukan!${NC}"
    exit 1
fi

load_envs
load_services_from_compose

# --- Daftar Volume ---
VOLUMES=(
    "app-mariadb-data"
    "app-redis-data"
)

# --- Fungsi Cek/Buat Volume (Silently) ---
check_volumes() {
    return 0 
}

# --- Fungsi Manajemen Volume (Recreate) ---
manage_volumes() {
    echo -e "${RED}=== MANAJEMEN VOLUME STACK: $STACK_NAME ===${NC}"
    echo -e "${YELLOW}PERINGATAN: Menghapus volume akan menghapus SEMUA data!${NC}"
    echo "------------------------------------------------"
    for i in "${!VOLUMES[@]}"; do
        echo -e "[$i] ${STACK_NAME}_${VOLUMES[$i]}"
    done
    echo "------------------------------------------------"
    read -p "Pilih angka untuk RECREATE (kosongkan untuk batal): " vol_idx

    if [[ -n "$vol_idx" ]] && [[ "$vol_idx" =~ ^[0-9]+$ ]] && [ "$vol_idx" -lt "${#VOLUMES[@]}" ]; then
        TARGET_VOL="${STACK_NAME}_${VOLUMES[$vol_idx]}"
        echo -e "${RED}[!] Menghapus volume $TARGET_VOL...${NC}"
        docker volume rm "$TARGET_VOL" 2>/dev/null
        echo -e "${GREEN}[+] Membuat ulang volume $TARGET_VOL...${NC}"
        docker volume create "$TARGET_VOL"
        read -p "Selesai. Tekan Enter untuk kembali."
    fi
}

# --- Fungsi Tampilan Checkbox ---
show_checkboxes() {
    local action_label="$1"
    local -n arr_ref=$2
    local -n sel_ref=$3
    echo -e "${YELLOW}=== STACK: $STACK_NAME | FILE: $COMPOSE_FILE ===${NC}"
    echo -e "${YELLOW}=== PILIH SERVICE UNTUK ${action_label^^} ===${NC}"
    echo "Ketik angka untuk (Un)Select, ketik 'a' untuk All, ketik 'r' untuk eksekusi."
    echo "------------------------------------------------"
    for i in "${!arr_ref[@]}"; do
        if [[ ${sel_ref[$i]} -eq 1 ]]; then
            echo -e "[$i] [${GREEN}x${NC}] ${arr_ref[$i]}"
        else
            echo -e "[$i] [ ] ${arr_ref[$i]}"
        fi
    done
    echo "------------------------------------------------"
}

# --- Logic Selector ---
service_selector() {
    local action_label="$1"
    local action_fn="$2"
    SELECTED_SVC=()
    for i in "${!SERVICES[@]}"; do SELECTED_SVC[$i]=0; done

    while true; do
        show_checkboxes "$action_label" SERVICES SELECTED_SVC
        read -p "Pilihan Anda (angka/a/r): " input
        [[ -z "$input" ]] && continue
        if [[ "$input" == "r" ]]; then break
        elif [[ "$input" == "a" ]]; then
            for i in "${!SERVICES[@]}"; do SELECTED_SVC[$i]=1; done
        elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 0 ] && [ "$input" -lt "${#SERVICES[@]}" ]; then
            [[ ${SELECTED_SVC[$input]} -eq 1 ]] && SELECTED_SVC[$input]=0 || SELECTED_SVC[$input]=1
        fi
    done

    CMD_SERVICES=""
    for i in "${!SERVICES[@]}"; do
        [[ ${SELECTED_SVC[$i]} -eq 1 ]] && CMD_SERVICES="$CMD_SERVICES ${SERVICES[$i]}"
    done

    if [[ -n "$CMD_SERVICES" ]]; then
        "$action_fn" "$CMD_SERVICES"
    else
        echo -e "${RED}[ERROR] Tidak ada yang dipilih!${NC}"
        sleep 1
    fi
}

# --- FUNGSI UTAMA DOCKER ---

run_docker() {
    load_envs
    ensure_app_network
    echo -e "${GREEN}[EXEC] Up: docker compose up -d $1${NC}"
    docker compose -f "$COMPOSE_FILE" up -d $1
}

restart_docker() {
    load_envs
    ensure_app_network
    echo -e "${GREEN}[EXEC] Restart: docker compose restart $1${NC}"
    docker compose -f "$COMPOSE_FILE" restart $1
}

rebuild_docker() {
    load_envs
    ensure_app_network
    echo -e "${GREEN}[EXEC] Rebuild & Up: docker compose up -d --build $1${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --build $1
}

recreate_docker() {
    load_envs
    ensure_app_network
    echo -e "${GREEN}[EXEC] Force Recreate: docker compose up -d --force-recreate $1${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --force-recreate $1
}

# --- LOGIC BARU: RELOAD (ZERO DOWNTIME - FIXED) ---
reload_docker() {
    load_envs
    ensure_app_network
    local selected_services="$1"
    
    if [[ -z "$selected_services" ]]; then
        selected_services="${SERVICES[*]}"
    fi

    echo -e "${CYAN}=== MULAI RELOAD CONFIGURATION (Zero Downtime) ===${NC}"

    for svc in $selected_services; do
        echo -e "${YELLOW}>> Reloading service: $svc ...${NC}"
        
        # Cek apakah container berjalan
        if ! docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -q "^$svc$"; then
            echo -e "${RED}   [SKIP] Service '$svc' tidak berjalan (Down).${NC}"
            continue
        fi

        case $svc in
            "nginx"|"load_balancer")
                # Nginx reload
                echo -e "${GREEN}   [EXEC] Reloading Nginx...${NC}"
                docker compose -f "$COMPOSE_FILE" exec "$svc" nginx -s reload
                ;;
            
            "wordpress"|"app")
                # PHP-FPM reload (USR2)
                echo -e "${GREEN}   [EXEC] Reloading App worker process...${NC}"
                docker compose -f "$COMPOSE_FILE" kill -s USR2 "$svc"
                ;;

            "nextjs"|"app-hmr")
                echo -e "${GREEN}   [EXEC] Restarting frontend/hmr service...${NC}"
                docker compose -f "$COMPOSE_FILE" restart "$svc"
                ;;

            "mariadb"|"redis")
                echo -e "${RED}   [WARN] Database/Store tidak support hot-reload. Gunakan Restart.${NC}"
                ;;
            
            *)
                echo -e "${BLUE}   [INFO] Restarting generic service $svc...${NC}"
                docker compose -f "$COMPOSE_FILE" restart "$svc"
                ;;
        esac
    done
    echo -e "${CYAN}=== RELOAD SELESAI ===${NC}"
}

# --- Main Menu ---
while true; do
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   CITRA KULINER - DOCKER MANAGER   ${NC}"
    echo -e "${BLUE}   STACK : $STACK_NAME              ${NC}"
    echo -e "${BLUE}   FILE  : $COMPOSE_FILE            ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "1. Jalankan SEMUA Service (Normal Up)"
    echo "2. Pilih Service Manual (Normal Up)"
    echo "3. Rebuild & Up SEMUA (Force Build)"
    echo "4. Rebuild & Up Manual (Force Build)"
    echo "5. Force Recreate Container SEMUA (Tanpa Rebuild Image)"
    echo "6. Force Recreate Container Manual (Tanpa Rebuild Image)"
    echo "----------------------------------------"
    echo "7. Restart Service Manual (Downtime)"
    echo "8. Restart SEMUA Service (Downtime)"
    echo -e "${CYAN}9. Reload Service Manual (Zero Downtime)${NC}"
    echo -e "${CYAN}10. Reload SEMUA Service (Zero Downtime)${NC}"
    echo "----------------------------------------"
    echo "11. Matikan Semua (Down)"
    echo "12. Kelola Volume (Buat Ulang/Recreate)"
    echo "13. Keluar"
    echo -e "----------------------------------------"
    read -p "Pilih menu [1-13]: " menu

    case $menu in
        1) run_docker ""; read -p "Press Enter...";;
        2) service_selector "Up" run_docker ;;
        3) rebuild_docker ""; read -p "Press Enter...";;
        4) service_selector "Rebuild" rebuild_docker ;;
        5) recreate_docker ""; read -p "Press Enter...";;
        6) service_selector "Recreate" recreate_docker ;;
        7) service_selector "Restart" restart_docker ;;
        8) restart_docker "" ; read -p "Press Enter...";;
        9) service_selector "Reload (Zero Downtime)" reload_docker; read -p "Press Enter..." ;;
        10) reload_docker ""; read -p "Press Enter..." ;;
        11) docker compose -f "$COMPOSE_FILE" down; read -p "Press Enter..." ;;
        12) manage_volumes ;;
        13) echo "Bye!"; exit 0 ;;
        *) echo "Pilihan tidak valid."; sleep 1 ;;
    esac
done