#!/bin/bash

# =========================================================
# DOCKER COMPOSE MANAGER (CHECKBOX STYLE)
# =========================================================

COMPOSE_FILE="docker-compose.portainer.yml"

# --- Konfigurasi Warna ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Script Directory & Root ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
INFRA_DIR="$ROOT_DIR/infra"

# --- Daftar Service Sesuai compose file yang dipilih ---
SERVICES=(
    "portainer"
)

# Status awal checkbox (0 = unselected, 1 = selected)
SELECTED=()
for i in "${!SERVICES[@]}"; do SELECTED[$i]=0; done

# --- Fungsi Load Environment ---
load_envs() {
    echo -e "${BLUE}[INFO] Loading environment variables from root project...${NC}"
    set -a
    [ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"
    [ -f "$ROOT_DIR/.env.backend" ] && source "$ROOT_DIR/.env.backend"
    [ -f "$ROOT_DIR/.env.devops" ] && source "$ROOT_DIR/.env.devops"
    set +a
}

# --- Fungsi Menampilkan Checkbox ---
show_checkboxes() {
    local action_label="$1"
    clear
    echo -e "${YELLOW}=== PILIH SERVICE YANG INGIN DIJALANKAN ===${NC}"
    echo "Menggunakan ${COMPOSE_FILE}"
    echo "Ketik angka untuk (Un)Select, ketik 'a' untuk All, ketik 'r' untuk ${action_label}."
    echo "------------------------------------------------"

    for i in "${!SERVICES[@]}"; do
        if [[ ${SELECTED[$i]} -eq 1 ]]; then
            echo -e "[$i] [${GREEN}x${NC}] ${SERVICES[$i]}"
        else
            echo -e "[$i] [ ] ${SERVICES[$i]}"
        fi
    done
    echo "------------------------------------------------"
}

# --- Logic Selector ---
service_selector() {
    local action_label="$1"
    local action_fn="$2"

    while true; do
        show_checkboxes "$action_label"
        read -p "Pilihan Anda (angka/a/r): " input

        [[ -z "$input" ]] && continue

        if [[ "$input" == "r" ]]; then
            break
        elif [[ "$input" == "a" ]]; then
            for i in "${!SERVICES[@]}"; do SELECTED[$i]=1; done
        elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 0 ] && [ "$input" -lt "${#SERVICES[@]}" ]; then
            if [[ ${SELECTED[$input]} -eq 1 ]]; then
                SELECTED[$input]=0
            else
                SELECTED[$input]=1
            fi
        fi
    done

    CMD_SERVICES=""
    COUNT=0
    for i in "${!SERVICES[@]}"; do
        if [[ ${SELECTED[$i]} -eq 1 ]]; then
            CMD_SERVICES="$CMD_SERVICES ${SERVICES[$i]}"
            ((COUNT++))
        fi
    done

    if [[ $COUNT -eq 0 ]]; then
        echo -e "${RED}[ERROR] Tidak ada service yang dipilih!${NC}"
        exit 1
    fi

    "$action_fn" "$CMD_SERVICES"
}

# --- Fungsi Eksekusi Docker ---
run_docker() {
    TARGETS=$1

    load_envs

    echo -e "${GREEN}[EXEC] Menjalankan: docker compose -f ${COMPOSE_FILE} up -d $TARGETS${NC}"

    docker compose -f "${COMPOSE_FILE}" up -d $TARGETS

    echo -e "${YELLOW}------------------------------------------------${NC}"
    echo -e "${GREEN}✅ Selesai! Cek status dengan: docker compose -f ${COMPOSE_FILE} ps${NC}"
}

restart_docker() {
    TARGETS=$1

    load_envs

    echo -e "${GREEN}[EXEC] Menjalankan: docker compose -f ${COMPOSE_FILE} restart $TARGETS${NC}"

    docker compose -f "${COMPOSE_FILE}" restart $TARGETS

    echo -e "${YELLOW}------------------------------------------------${NC}"
    echo -e "${GREEN}✅ Restart selesai! Cek status dengan: docker compose -f ${COMPOSE_FILE} ps${NC}"
}

# --- Main Menu ---
clear
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   APP BOILERPLATE - DOCKER MANAGER   ${NC}"
echo -e "${BLUE}========================================${NC}"
echo "1. Jalankan SEMUA Service (Full Stack)"
echo "2. Pilih Service Manual (Checkbox)"
echo "3. Restart Service Manual (Checkbox)"
echo "4. Restart SEMUA Service"
echo "5. Matikan Semua (Down)"
echo "6. Keluar"
echo -e "----------------------------------------"
read -p "Pilih menu [1-6]: " menu

case $menu in
    1)
        run_docker ""
        ;;
    2)
        service_selector "Menjalankan" run_docker
        ;;
    3)
        service_selector "Restart" restart_docker
        ;;
    4)
        restart_docker ""
        ;;
    5)
        echo -e "${RED}[STOP] Mematikan semua container...${NC}"
        docker compose -f "${COMPOSE_FILE}" down
        ;;
    6)
        echo "Bye!"
        exit 0
        ;;
    *)
        echo "Pilihan tidak valid."
        ;;
esac
