#!/bin/bash

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Banner
echo -e "${PURPLE}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║        APP BOILERPLATE - DEPLOY SCRIPTS MENU          ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOY_SCRIPTS_DIR="${SCRIPT_DIR}/scripts/deploy"

# Check if deploy scripts directory exists
if [ ! -d "$DEPLOY_SCRIPTS_DIR" ]; then
    echo -e "${RED}Error: scripts/deploy directory not found!${NC}"
    exit 1
fi

# If an argument is provided, run that specific script
if [ -n "${1:-}" ]; then
    script_path="$DEPLOY_SCRIPTS_DIR/$1"
    if [ -f "$script_path" ]; then
        shift # Remove script name from arguments
        chmod +x "$script_path"
        bash "$script_path" "$@"
        exit $?
    else
        echo -e "${RED}Error: Script '$1' not found in $DEPLOY_SCRIPTS_DIR${NC}"
        exit 1
    fi
fi

# List all .sh files in deploy directory
echo -e "${YELLOW}Available deployment scripts:${NC}\n"

# Create array of scripts
scripts=()
i=1
for script in "${DEPLOY_SCRIPTS_DIR}"/*.sh; do
    if [ -f "$script" ]; then
        filename=$(basename "$script")
        scripts+=("$filename")
        echo -e "  [${i}] ${filename}"
        ((i++))
    fi
done

if [ ${#scripts[@]} -eq 0 ]; then
    echo -e "${RED}No scripts found in scripts/deploy!${NC}"
    exit 0
fi

echo ""
read -p "Select a script to run (1-${#scripts[@]}): " choice

if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#scripts[@]}" ]; then
    selected_script="${scripts[$((choice-1))]}"
    script_path="$DEPLOY_SCRIPTS_DIR/$selected_script"
    
    echo -e "\n${GREEN}Running $selected_script...${NC}\n"
    chmod +x "$script_path"
    bash "$script_path"
else
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi
