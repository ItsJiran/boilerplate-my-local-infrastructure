#!/bin/bash

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║         APP BOILERPLATE - RUN SCRIPTS MENU             ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RUN_SCRIPTS_DIR="${SCRIPT_DIR}/scripts/run"

# Check if run scripts directory exists
if [ ! -d "$RUN_SCRIPTS_DIR" ]; then
    echo -e "${RED}Error: scripts/run directory not found!${NC}"
    exit 1
fi

# If an argument is provided, run that specific script
if [ -n "${1:-}" ]; then
    script_path="$RUN_SCRIPTS_DIR/$1"
    if [ -f "$script_path" ]; then
        shift # Remove script name from arguments
        chmod +x "$script_path"
        bash "$script_path" "$@"
        exit $?
    else
        echo -e "${RED}Error: Script '$1' not found in $RUN_SCRIPTS_DIR${NC}"
        exit 1
    fi
fi

# List all .sh files in run directory
echo -e "${YELLOW}Available run scripts:${NC}\n"

# Create array of scripts
scripts=()
i=1
for script in "${RUN_SCRIPTS_DIR}"/*.sh; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        scripts+=("$script")
        
        # Extract description from script if exists (looking for # Description: comment)
        description=$(grep -m 1 "^# Description:" "$script" | sed 's/# Description: //')
        
        if [ -z "$description" ]; then
            echo -e "${GREEN}[$i]${NC} $script_name"
        else
            echo -e "${GREEN}[$i]${NC} $script_name"
            echo -e "    ${BLUE}→${NC} $description"
        fi
        ((i++))
    fi
done

# Add exit option
echo -e "\n${GREEN}[0]${NC} Exit"

# Get total count
total=${#scripts[@]}

if [ $total -eq 0 ]; then
    echo -e "\n${RED}No scripts found in scripts/run/${NC}"
    exit 1
fi

# Prompt for selection
echo -e "\n${YELLOW}Enter your choice [0-$total]:${NC} "
read -r choice

# Validate input
if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Invalid input. Please enter a number.${NC}"
    exit 1
fi

# Exit if 0
if [ "$choice" -eq 0 ]; then
    echo -e "${BLUE}Exiting...${NC}"
    exit 0
fi

# Check if choice is valid
if [ "$choice" -lt 1 ] || [ "$choice" -gt $total ]; then
    echo -e "${RED}Invalid choice. Please select a number between 0 and $total${NC}"
    exit 1
fi

# Get selected script
selected_script="${scripts[$((choice-1))]}"
script_name=$(basename "$selected_script")

echo -e "\n${GREEN}Running: $script_name${NC}\n"
echo "═══════════════════════════════════════════════════════"

# Make script executable and run it
chmod +x "$selected_script"
bash "$selected_script"

exit_code=$?

echo ""
echo "═══════════════════════════════════════════════════════"
if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ Script completed successfully${NC}"
else
    echo -e "${RED}✗ Script failed with exit code: $exit_code${NC}"
fi
