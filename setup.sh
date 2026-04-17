#!/bin/bash

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║        APP BOILERPLATE - SETUP SCRIPTS MENU            ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SETUP_SCRIPTS_DIR="${SCRIPT_DIR}/scripts/setup"

# Check if setup scripts directory exists
if [ ! -d "$SETUP_SCRIPTS_DIR" ]; then
    echo -e "${RED}Error: scripts/setup directory not found!${NC}"
    exit 1
fi

# If an argument is provided, run that specific script
if [ -n "${1:-}" ]; then
    script_path="$SETUP_SCRIPTS_DIR/$1"
    if [ -f "$script_path" ]; then
        shift # Remove script name from arguments
        chmod +x "$script_path"
        bash "$script_path" "$@"
        exit $?
    else
        echo -e "${RED}Error: Script '$1' not found in $SETUP_SCRIPTS_DIR${NC}"
        exit 1
    fi
fi

# List all .sh files in setup directory
echo -e "${YELLOW}Available setup scripts:${NC}\n"

# Create array of scripts
scripts=()
i=1
for script in "${SETUP_SCRIPTS_DIR}"/*.sh; do
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

# Add special options
echo -e "\n${CYAN}[A]${NC} Run ALL setup scripts (in order)"
echo -e "${GREEN}[0]${NC} Exit"

# Get total count
total=${#scripts[@]}

if [ $total -eq 0 ]; then
    echo -e "\n${RED}No scripts found in scripts/setup/${NC}"
    exit 1
fi

# Prompt for selection
echo -e "\n${YELLOW}Enter your choice [0-$total or A]:${NC} "
read -r choice

# Convert to uppercase for A option
choice_upper=$(echo "$choice" | tr '[:lower:]' '[:upper:]')

# Exit if 0
if [ "$choice" = "0" ]; then
    echo -e "${BLUE}Exiting...${NC}"
    exit 0
fi

# Run all scripts if A
if [ "$choice_upper" = "A" ]; then
    echo -e "\n${CYAN}Running ALL setup scripts...${NC}\n"
    echo "═══════════════════════════════════════════════════════"
    
    failed_scripts=()
    for script in "${scripts[@]}"; do
        script_name=$(basename "$script")
        echo -e "\n${GREEN}► Running: $script_name${NC}"
        
        chmod +x "$script"
        bash "$script"
        
        if [ $? -ne 0 ]; then
            failed_scripts+=("$script_name")
            echo -e "${RED}✗ Failed: $script_name${NC}"
        else
            echo -e "${GREEN}✓ Completed: $script_name${NC}"
        fi
    done
    
    echo ""
    echo "═══════════════════════════════════════════════════════"
    
    if [ ${#failed_scripts[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ All setup scripts completed successfully${NC}"
    else
        echo -e "${RED}✗ Some scripts failed:${NC}"
        for failed in "${failed_scripts[@]}"; do
            echo -e "${RED}  - $failed${NC}"
        done
        exit 1
    fi
    
    exit 0
fi

# Validate input for single script selection
if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Invalid input. Please enter a number or 'A'.${NC}"
    exit 1
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
