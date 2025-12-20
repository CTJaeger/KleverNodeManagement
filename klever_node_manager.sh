#!/bin/bash

################################################################################
#                     Klever Node Management Suite                             #
#                      Created by CryptoJaeger^^                               #
################################################################################

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
WHITE='\e[37m'
RESET='\e[0m'
BOLD='\e[1m'

# Ensure PATH is set correctly
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Display header
display_header() {
    clear
    echo -e "${GREEN}${BOLD}************************************************${RESET}"
    echo -e "${GREEN}${BOLD}*        Klever Node Management Suite          *${RESET}"
    echo -e "${GREEN}${BOLD}*           Created by CryptoJaeger^^          *${RESET}"
    echo -e "${GREEN}${BOLD}************************************************${RESET}"
    echo
}

# Progress bar function
show_progress() {
    local duration=$1
    local message=$2
    local progress=0
    local bar_length=50
    
    echo -ne "${CYAN}${message}${RESET} "
    while [ $progress -le 100 ]; do
        local filled=$((progress * bar_length / 100))
        local empty=$((bar_length - filled))
        printf "\r${CYAN}${message}${RESET} ["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] ${progress}%%"
        progress=$((progress + 2))
        sleep $(echo "$duration / 50" | bc -l)
    done
    echo -e " ${GREEN}✓${RESET}"
}

# Spinner for indeterminate progress
show_spinner() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    
    echo -ne "${CYAN}${message}${RESET} "
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}${message}${RESET} ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r${CYAN}${message}${RESET} ${GREEN}✓${RESET}\n"
}

# Wait for user
press_any_key() {
    echo
    echo -e "${YELLOW}Press any key to continue...${RESET}"
    read -n 1 -s
}

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}Error: This script must be run as root or with sudo.${RESET}"
        exit 1
    fi
}

################################################################################
# SYSTEM CHECK FUNCTIONS
################################################################################

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        CODENAME=$VERSION_CODENAME
    else
        echo -e "${RED}Cannot detect Linux distribution. Exiting.${RESET}"
        exit 1
    fi
    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        echo -e "${RED}Unsupported distribution: $DISTRO. Only Ubuntu and Debian are supported.${RESET}"
        exit 1
    fi
}

# Check if a port is available
check_port() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1
    fi
    return 0
}

# Check if Docker is installed
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker is not installed. Installing Docker now...${RESET}"
        install_docker
    fi
}

# Install Docker
install_docker() {
    echo -e "${CYAN}Installing Docker...${RESET}"
    
    (
        apt-get update > /dev/null 2>&1
        apt-get install -y ca-certificates curl > /dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$DISTRO/gpg -o /etc/apt/keyrings/docker.asc > /dev/null 2>&1
        chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO $CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update > /dev/null 2>&1
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    ) &
    
    show_spinner $! "Installing Docker"
    
    if [ $? -eq 0 ]; then
        systemctl enable --now docker > /dev/null 2>&1
        if ! systemctl is-active --quiet docker; then
            echo -e "${RED}Docker service failed to start. Please check manually.${RESET}"
            exit 1
        fi
        echo -e "${GREEN}Docker installed successfully.${RESET}"
        
        # Add the original user to docker group
        if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
            usermod -aG docker "$SUDO_USER" 2>/dev/null || true
            echo -e "${YELLOW}User $SUDO_USER added to docker group. Log out and back in for changes to take effect.${RESET}"
        fi
    else
        echo -e "${RED}Failed to install Docker. Exiting.${RESET}"
        exit 1
    fi
}

# Check and install jq
check_jq_installed() {
    if ! command -v jq &> /dev/null; then
        echo -e "${CYAN}Installing jq...${RESET}"
        (
            apt-get update > /dev/null 2>&1
            apt-get install -y jq > /dev/null 2>&1
        ) &
        show_spinner $! "Installing jq"
        
        if ! command -v jq &> /dev/null; then
            echo -e "${RED}Failed to install jq. Please install it manually.${RESET}"
            exit 1
        fi
        echo -e "${GREEN}jq installed successfully.${RESET}"
    fi
}

# Check and install bc for calculations
check_bc_installed() {
    if ! command -v bc &> /dev/null; then
        apt-get install -y bc > /dev/null 2>&1
    fi
}

################################################################################
# NODE DISCOVERY FUNCTIONS
################################################################################

# Find all Klever node directories and containers
find_node_directories() {
    docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' | grep 'kleverapp/klever-go' | while read container_id image container_name; do
        dirs=$(docker inspect "$container_id" 2>/dev/null | jq -r '.[].Mounts[] | select(.Destination | startswith("/opt/klever-blockchain")) | .Source' 2>/dev/null | while read dir; do dirname "$dir"; done | sort -u)
        for dir in $dirs; do
            if [ -d "$dir" ]; then
                echo "$dir $container_name"
            fi
        done
    done | sort -u
}

# Extract node parameters from container
extract_node_parameters() {
    local container_name=$1
    local node_name=$2

    # Extract arguments
    local args
    args=$(docker inspect "$container_name" 2>/dev/null | jq -r '.[].Args | join(" ")' 2>/dev/null)
    if [[ $? -ne 0 || -z "$args" ]]; then
        args=$(docker inspect "$container_name" 2>/dev/null | jq -r '.[].Config.Cmd | join(" ")' 2>/dev/null)
        if [[ $? -ne 0 || -z "$args" ]]; then
            args=""
        fi
    fi

    # Extract REST API port
    local rest_api_port
    rest_api_port=$(echo "$args" | grep -oE -- '--rest-api-interface=0\.0\.0\.0:[0-9]+' | grep -oE '[0-9]+$' || echo "8080")

    # Extract redundancy level
    local redundancy
    redundancy=$(echo "$args" | grep -oE -- '--redundancy-level=[0-1]' | grep -oE '[0-1]$' || echo "")
    if [[ -n "$redundancy" ]]; then
        redundancy="--redundancy-level=$redundancy"
    else
        redundancy=""
    fi

    # Extract display name
    local display_name
    display_name=$(echo "$args" | grep -oE -- '--display-name=[^ ]*' | sed 's/--display-name=//' || echo "$node_name")

    echo "$rest_api_port|$redundancy|$display_name"
}

################################################################################
# PERMISSIONS FUNCTIONS
################################################################################

# Fix permissions for a node directory
fix_node_permissions() {
    local node_dir=$1
    local node_name=$(basename "$node_dir")
    
    echo -e "${CYAN}Fixing permissions for $node_name...${RESET}"
    
    # Check and create directories if they don't exist
    for subdir in config db logs wallet; do
        if [ ! -d "$node_dir/$subdir" ]; then
            mkdir -p "$node_dir/$subdir"
            echo -e "${YELLOW}  Created missing directory: $subdir${RESET}"
        fi
    done
    
    # Set ownership to 999:999
    chown -R 999:999 "$node_dir" 2>/dev/null
    chown -R 999:999 "$node_dir/config" 2>/dev/null
    chown -R 999:999 "$node_dir/db" 2>/dev/null
    chown -R 999:999 "$node_dir/logs" 2>/dev/null
    chown -R 999:999 "$node_dir/wallet" 2>/dev/null
    
    # Verify permissions
    local all_correct=true
    for subdir in config db logs wallet; do
        if [ -d "$node_dir/$subdir" ]; then
            local owner=$(stat -c '%u:%g' "$node_dir/$subdir" 2>/dev/null)
            if [ "$owner" != "999:999" ]; then
                echo -e "${RED}  ✗ Failed to set permissions for $subdir (current: $owner)${RESET}"
                all_correct=false
            else
                echo -e "${GREEN}  ✓ $subdir permissions correct (999:999)${RESET}"
            fi
        fi
    done
    
    if [ "$all_correct" = true ]; then
        echo -e "${GREEN}All permissions set correctly for $node_name.${RESET}"
        return 0
    else
        echo -e "${YELLOW}Some permissions could not be verified for $node_name.${RESET}"
        return 1
    fi
}

################################################################################
# CREATE NODES MODULE
################################################################################

# Find next available node number and port
find_next_available_node() {
    local base_path=$1
    local existing_nodes=$(find_node_directories 2>/dev/null)
    
    # Find highest existing node number
    local max_node_num=0
    local max_port=8079
    
    if [[ -n "$existing_nodes" ]]; then
        while IFS= read -r line; do
            local node_dir=$(echo "$line" | awk '{print $1}')
            local container_name=$(echo "$line" | awk '{print $2}')
            local node_name=$(basename "$node_dir")
            
            # Extract node number
            if [[ $node_name =~ node([0-9]+) ]]; then
                local node_num=${BASH_REMATCH[1]}
                if [ $node_num -gt $max_node_num ]; then
                    max_node_num=$node_num
                fi
            fi
            
            # Extract port
            local params=$(extract_node_parameters "$container_name" "$node_name")
            local port=$(echo "$params" | cut -d'|' -f1)
            if [ $port -gt $max_port ]; then
                max_port=$port
            fi
        done <<< "$existing_nodes"
    fi
    
    local next_node_num=$((max_node_num + 1))
    local next_port=$((max_port + 1))
    
    echo "$next_node_num|$next_port"
}

create_node() {
    local node_number=$1
    local base_path=$2
    local redundancy=$3
    local generate_keys=$4
    local start_port=$5  # New parameter for starting port
    local node_name="node$node_number"
    local rest_api_port=${start_port:-$((8080 + $node_number - 1))}
    local node_path="$base_path/$node_name"

    echo
    echo -e "${CYAN}${BOLD}Creating $node_name...${RESET}"
    
    # Check if node directory already exists
    if [ -d "$node_path" ]; then
        echo -e "${RED}✗ Directory $node_path already exists. Skipping.${RESET}"
        return 1
    fi
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^klever-${node_name}$"; then
        echo -e "${RED}✗ Container klever-$node_name already exists. Skipping.${RESET}"
        return 1
    fi

    # Check if port is available
    if ! check_port $rest_api_port; then
        echo -e "${RED}✗ Port $rest_api_port is already in use.${RESET}"
        echo -e "${YELLOW}  Please use a different port or stop the service using this port.${RESET}"
        return 1
    fi

    # Create directories
    echo -e "${CYAN}  Creating directory structure...${RESET}"
    mkdir -p "$node_path/config" "$node_path/db" "$node_path/logs" "$node_path/wallet"
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to create directories.${RESET}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Directories created${RESET}"

    # Fix permissions
    fix_node_permissions "$node_path"

    # Download configuration
    echo -e "${CYAN}  Downloading configuration...${RESET}"
    local config_downloaded=false
    
    # Try primary source
    if curl -k -s -f -o /tmp/config_${node_name}.tar.gz "https://backup.mainnet.klever.org/config.mainnet.108.tar.gz" 2>/dev/null; then
        config_downloaded=true
        echo -e "${GREEN}  ✓ Configuration downloaded from primary source${RESET}"
    else
        echo -e "${YELLOW}  Primary source unavailable, trying secondary...${RESET}"
        if curl -s -f -o /tmp/config_${node_name}.tar.gz "https://klever-radar.de/software/nodes/config.tar.gz" 2>/dev/null; then
            config_downloaded=true
            echo -e "${GREEN}  ✓ Configuration downloaded from secondary source${RESET}"
        fi
    fi
    
    if [ "$config_downloaded" = false ]; then
        echo -e "${RED}✗ Could not download configuration file.${RESET}"
        return 1
    fi

    # Extract configuration
    echo -e "${CYAN}  Extracting configuration...${RESET}"
    pushd "$node_path/config" > /dev/null
    tar -xzf /tmp/config_${node_name}.tar.gz --strip-components=1 2>/dev/null
    local extract_status=$?
    popd > /dev/null
    rm -f /tmp/config_${node_name}.tar.gz
    
    if [ $extract_status -ne 0 ]; then
        echo -e "${RED}✗ Failed to extract configuration.${RESET}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Configuration extracted${RESET}"

    # Generate validator keys if needed
    if [[ "$generate_keys" == "y" ]]; then
        echo -e "${CYAN}  Generating validator keys...${RESET}"
        docker run -it --rm -v "$node_path/config:/opt/klever-blockchain" \
            --user "999:999" \
            --entrypoint='' kleverapp/klever-go:latest keygenerator > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ Failed to generate validator key.${RESET}"
            return 1
        fi
        echo -e "${GREEN}  ✓ Validator keys generated${RESET}"
    fi

    # Start Docker container
    echo -e "${CYAN}  Starting Docker container...${RESET}"
    docker run -it -d \
        --restart unless-stopped \
        --user "999:999" \
        --name klever-$node_name \
        -v "$node_path/config:/opt/klever-blockchain/config/node" \
        -v "$node_path/db:/opt/klever-blockchain/db" \
        -v "$node_path/logs:/opt/klever-blockchain/logs" \
        -v "$node_path/wallet:/opt/klever-blockchain/wallet" \
        --network=host \
        --entrypoint=/usr/local/bin/validator \
        kleverapp/klever-go:latest \
        '--log-save' '--use-log-view' "--rest-api-interface=0.0.0.0:$rest_api_port" \
        "--display-name=$node_name" '--start-in-epoch' $redundancy > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Container started successfully${RESET}"
        echo -e "${GREEN}${BOLD}✓ Node $node_name created successfully!${RESET}"
        return 0
    else
        echo -e "${RED}✗ Failed to start Docker container.${RESET}"
        return 1
    fi
}

module_create_nodes() {
    display_header
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}           CREATE NEW KLEVER NODES             ${RESET}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo

    # Check for existing nodes first
    echo -e "${CYAN}Checking for existing Klever nodes...${RESET}"
    local existing_nodes=$(find_node_directories 2>/dev/null)
    
    if [[ -n "$existing_nodes" ]]; then
        echo -e "${YELLOW}${BOLD}Existing nodes detected:${RESET}"
        echo
        
        declare -a used_ports
        declare -a existing_node_names
        
        while IFS= read -r line; do
            local node_dir=$(echo "$line" | awk '{print $1}')
            local container_name=$(echo "$line" | awk '{print $2}')
            local node_name=$(basename "$node_dir")
            
            local params=$(extract_node_parameters "$container_name" "$node_name")
            local rest_api_port=$(echo "$params" | cut -d'|' -f1)
            local redundancy=$(echo "$params" | cut -d'|' -f2)
            local status=$(get_container_status "$container_name")
            
            used_ports+=("$rest_api_port")
            existing_node_names+=("$node_name")
            
            if [ "$status" == "running" ]; then
                echo -e "  ${GREEN}•${RESET} ${WHITE}$node_name${RESET} - Port: ${CYAN}$rest_api_port${RESET} - Status: ${GREEN}Running${RESET}"
            else
                echo -e "  ${YELLOW}•${RESET} ${WHITE}$node_name${RESET} - Port: ${CYAN}$rest_api_port${RESET} - Status: ${RED}Stopped${RESET}"
            fi
            
            if [[ "$redundancy" == "--redundancy-level=1" ]]; then
                echo -e "    ${YELLOW}(Fallback Node)${RESET}"
            fi
        done <<< "$existing_nodes"
        
        # Find next available port
        local max_port=8079
        for port in "${used_ports[@]}"; do
            if [ $port -gt $max_port ]; then
                max_port=$port
            fi
        done
        local next_free_port=$((max_port + 1))
        
        echo
        echo -e "${YELLOW}Used ports: ${WHITE}${used_ports[*]}${RESET}"
        echo -e "${YELLOW}Existing node names: ${WHITE}${existing_node_names[*]}${RESET}"
        echo
        echo -e "${CYAN}New nodes will automatically use the next available ports starting from ${WHITE}$next_free_port${CYAN}.${RESET}"
        echo
        
        while true; do
            read -p $'\e[35mDo you want to continue creating additional nodes? (y/n): \e[0m' continue_create
            if [[ "$continue_create" == "y" || "$continue_create" == "n" ]]; then
                break
            fi
            echo -e "${RED}Please enter 'y' or 'n'.${RESET}"
        done
        
        if [[ "$continue_create" == "n" ]]; then
            echo -e "${YELLOW}Node creation cancelled.${RESET}"
            press_any_key
            return 0
        fi
        echo
    else
        echo -e "${GREEN}No existing nodes found. You can create new nodes.${RESET}"
        echo
    fi

    # Detect distribution
    detect_distro

    # Ask for installation directory
    read -p $'\e[35mEnter installation directory (default: /opt): \e[0m' base_path
    base_path=${base_path:-/opt}
    
    if [ ! -d "$base_path" ]; then
        mkdir -p "$base_path"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to create installation directory $base_path.${RESET}"
            press_any_key
            return 1
        fi
    fi
    echo -e "${GREEN}Installation directory: $base_path${RESET}"
    echo

    # Check Docker
    check_docker_installed
    echo

    # Pull Docker image
    echo -e "${CYAN}Pulling latest Docker image...${RESET}"
    (docker pull kleverapp/klever-go:latest > /dev/null 2>&1) &
    show_spinner $! "Pulling kleverapp/klever-go:latest"
    echo

    # Ask for number of nodes
    while true; do
        read -p $'\e[35mHow many nodes do you want to create? \e[0m' num_nodes
        if [[ $num_nodes =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo -e "${RED}Please enter a positive integer.${RESET}"
        fi
    done
    echo

    # Ask if these are fallback nodes
    echo -e "${YELLOW}${BOLD}Important: Fallback nodes vs. Normal nodes${RESET}"
    echo -e "${YELLOW}  • Normal nodes: Active validators (--redundancy-level not set)${RESET}"
    echo -e "${YELLOW}  • Fallback nodes: Backup validators (--redundancy-level=1)${RESET}"
    echo
    while true; do
        read -p $'\e[35mAre these fallback nodes? (y/n): \e[0m' fallback_choice
        if [[ "$fallback_choice" == "y" || "$fallback_choice" == "n" ]]; then
            break
        fi
        echo -e "${RED}Please enter 'y' or 'n'.${RESET}"
    done

    if [[ $fallback_choice == "y" ]]; then
        redundancy="--redundancy-level=1"
        generate_keys="n"
        echo -e "${CYAN}Fallback nodes will be created with redundancy level 1.${RESET}"
    else
        redundancy=""
        echo
        while true; do
            read -p $'\e[35mDo you need to generate new BLS validator keys? (y/n): \e[0m' generate_keys
            if [[ "$generate_keys" == "y" || "$generate_keys" == "n" ]]; then
                break
            fi
            echo -e "${RED}Please enter 'y' or 'n'.${RESET}"
        done
    fi
    echo

    # Find next available node number and port
    local next_info=$(find_next_available_node "$base_path")
    local next_node_num=$(echo "$next_info" | cut -d'|' -f1)
    local next_port=$(echo "$next_info" | cut -d'|' -f2)
    
    local end_node_num=$((next_node_num + num_nodes - 1))
    local end_port=$((next_port + num_nodes - 1))

    # Summary
    echo -e "${CYAN}${BOLD}Summary:${RESET}"
    echo -e "${CYAN}  • Installation path: ${WHITE}$base_path${RESET}"
    echo -e "${CYAN}  • Number of nodes: ${WHITE}$num_nodes${RESET}"
    echo -e "${CYAN}  • Node type: ${WHITE}$([ "$fallback_choice" = "y" ] && echo "Fallback (redundancy-level=1)" || echo "Normal (active validator)")${RESET}"
    echo -e "${CYAN}  • Generate new keys: ${WHITE}$([ "$generate_keys" = "y" ] && echo "Yes" || echo "No")${RESET}"
    echo -e "${CYAN}  • Node names: ${WHITE}node$next_node_num - node$end_node_num${RESET}"
    echo -e "${CYAN}  • REST API ports: ${WHITE}$next_port - $end_port${RESET}"
    echo
    
    while true; do
        read -p $'\e[35mProceed with node creation? (y/n): \e[0m' confirm
        if [[ "$confirm" == "y" || "$confirm" == "n" ]]; then
            break
        fi
        echo -e "${RED}Please enter 'y' or 'n'.${RESET}"
    done

    if [[ "$confirm" == "n" ]]; then
        echo -e "${YELLOW}Node creation cancelled.${RESET}"
        press_any_key
        return 0
    fi

    echo
    echo -e "${CYAN}${BOLD}Creating nodes...${RESET}"
    echo

    # Create nodes with intelligent numbering and port assignment
    local success_count=0
    local fail_count=0
    
    for ((i=0; i<$num_nodes; i++)); do
        local current_node_num=$((next_node_num + i))
        local current_port=$((next_port + i))
        if create_node $current_node_num "$base_path" "$redundancy" "$generate_keys" $current_port; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    echo
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}Node Creation Summary:${RESET}"
    echo -e "${GREEN}  ✓ Successfully created: $success_count${RESET}"
    if [ $fail_count -gt 0 ]; then
        echo -e "${RED}  ✗ Failed: $fail_count${RESET}"
    fi
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo

    # Important warnings
    if [[ "$fallback_choice" == "y" ]]; then
        echo -e "${YELLOW}${BOLD}⚠ IMPORTANT:${RESET}"
        echo -e "${YELLOW}Please ensure the 'validatorKey.pem' file is placed in each fallback node's config directory.${RESET}"
        echo -e "${YELLOW}After placing the key, restart the node: ${WHITE}docker restart klever-node1${RESET}"
    elif [[ "$generate_keys" == "y" ]]; then
        echo -e "${YELLOW}${BOLD}⚠ IMPORTANT:${RESET}"
        echo -e "${YELLOW}New 'validatorKey.pem' files have been generated in each node's config directory.${RESET}"
        echo -e "${YELLOW}Please ensure these keys are backed up securely!${RESET}"
    else
        echo -e "${YELLOW}${BOLD}⚠ IMPORTANT:${RESET}"
        echo -e "${YELLOW}Please ensure the 'validatorKey.pem' file is placed in each node's config directory.${RESET}"
        echo -e "${YELLOW}After placing the key, restart the node: ${WHITE}docker restart klever-node1${RESET}"
    fi
    
    echo
    echo -e "${CYAN}${BOLD}Node Management Commands:${RESET}"
    echo -e "${WHITE}  • Stop a node:  ${CYAN}docker stop klever-node<number>${RESET}"
    echo -e "${WHITE}  • Start a node: ${CYAN}docker start klever-node<number>${RESET}"
    echo -e "${WHITE}  • View logs:    ${CYAN}docker logs -f --tail 50 klever-node<number>${RESET}"
    
    press_any_key
}

################################################################################
# UPDATE NODES MODULE
################################################################################

update_node() {
    local node_dir=$1
    local container_name=$2
    local rest_api_port=$3
    local redundancy=$4
    local display_name=$5
    local node_name=$(basename "$node_dir")

    echo
    echo -e "${CYAN}${BOLD}Updating $node_name (container: $container_name)...${RESET}"

    # Download configuration
    echo -e "${CYAN}  Downloading latest configuration...${RESET}"
    if ! curl -k -s -f -o /tmp/config_update_${node_name}.tar.gz "https://backup.mainnet.klever.org/config.mainnet.108.tar.gz" 2>/dev/null; then
        echo -e "${RED}✗ Failed to download configuration file.${RESET}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Configuration downloaded${RESET}"

    # Extract configuration
    echo -e "${CYAN}  Extracting configuration...${RESET}"
    pushd "$node_dir" > /dev/null
    tar -xzf /tmp/config_update_${node_name}.tar.gz --strip-components=1 -C ./config 2>/dev/null
    local extract_status=$?
    popd > /dev/null
    rm -f /tmp/config_update_${node_name}.tar.gz
    
    if [ $extract_status -ne 0 ]; then
        echo -e "${RED}✗ Failed to extract configuration.${RESET}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Configuration extracted${RESET}"

    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${CYAN}  Stopping container...${RESET}"
        docker stop $container_name > /dev/null 2>&1
        echo -e "${GREEN}  ✓ Container stopped${RESET}"
        
        echo -e "${CYAN}  Removing old container...${RESET}"
        docker rm $container_name > /dev/null 2>&1
        echo -e "${GREEN}  ✓ Container removed${RESET}"
    fi

    # Fix permissions
    fix_node_permissions "$node_dir"

    # Pull latest image
    echo -e "${CYAN}  Pulling latest Docker image...${RESET}"
    (docker pull kleverapp/klever-go:latest > /dev/null 2>&1) &
    show_spinner $! "  Pulling kleverapp/klever-go:latest"

    # Start new container
    echo -e "${CYAN}  Starting new container...${RESET}"
    echo -e "${CYAN}    REST API Port: ${WHITE}0.0.0.0:$rest_api_port${RESET}"
    if [[ -n "$redundancy" ]]; then
        echo -e "${CYAN}    Redundancy: ${WHITE}$redundancy${RESET}"
    else
        echo -e "${CYAN}    Redundancy: ${WHITE}None (Normal validator)${RESET}"
    fi
    echo -e "${CYAN}    Display Name: ${WHITE}$display_name${RESET}"
    
    docker run -it -d \
        --restart unless-stopped \
        --user "999:999" \
        --name $container_name \
        -v $node_dir/config:/opt/klever-blockchain/config/node \
        -v $node_dir/db:/opt/klever-blockchain/db \
        -v $node_dir/logs:/opt/klever-blockchain/logs \
        -v $node_dir/wallet:/opt/klever-blockchain/wallet \
        --network=host \
        --entrypoint=/usr/local/bin/validator \
        kleverapp/klever-go:latest \
        '--log-save' '--use-log-view' "--rest-api-interface=0.0.0.0:$rest_api_port" \
        "--display-name=$display_name" '--start-in-epoch' $redundancy > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Container started${RESET}"
        echo -e "${GREEN}${BOLD}✓ Node $node_name updated successfully!${RESET}"
        return 0
    else
        echo -e "${RED}✗ Failed to start container.${RESET}"
        return 1
    fi
}

module_update_nodes() {
    display_header
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}         UPDATE EXISTING KLEVER NODES          ${RESET}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo

    # Check prerequisites
    check_jq_installed
    echo

    # Find nodes
    echo -e "${CYAN}Searching for Klever nodes...${RESET}"
    local node_info
    node_info=$(find_node_directories)
    
    if [[ -z "$node_info" ]]; then
        echo -e "${RED}No Klever nodes found.${RESET}"
        echo -e "${YELLOW}Please create nodes first using option 1.${RESET}"
        press_any_key
        return 1
    fi

    # Parse and display nodes
    declare -a nodes_to_update
    local fallback_count=0
    local normal_count=0
    
    echo -e "${GREEN}Found Klever nodes:${RESET}"
    echo

    while IFS= read -r line; do
        local node_dir=$(echo "$line" | awk '{print $1}')
        local container_name=$(echo "$line" | awk '{print $2}')
        local node_name=$(basename "$node_dir")
        
        local params=$(extract_node_parameters "$container_name" "$node_name")
        local rest_api_port=$(echo "$params" | cut -d'|' -f1)
        local redundancy=$(echo "$params" | cut -d'|' -f2)
        local display_name=$(echo "$params" | cut -d'|' -f3)
        
        echo -e "${CYAN}${BOLD}Node: $node_name${RESET}"
        echo -e "${WHITE}  Path:          ${CYAN}$node_dir${RESET}"
        echo -e "${WHITE}  Container:     ${CYAN}$container_name${RESET}"
        echo -e "${WHITE}  REST API Port: ${CYAN}$rest_api_port${RESET}"
        
        if [[ "$redundancy" == "--redundancy-level=1" ]]; then
            echo -e "${WHITE}  Type:          ${YELLOW}Fallback Node (redundancy-level=1)${RESET}"
            ((fallback_count++))
        else
            echo -e "${WHITE}  Type:          ${GREEN}Normal Validator${RESET}"
            ((normal_count++))
        fi
        
        echo -e "${WHITE}  Display Name:  ${CYAN}$display_name${RESET}"
        echo
        
        nodes_to_update+=("$node_dir|$container_name|$rest_api_port|$redundancy|$display_name")
    done <<< "$node_info"

    # Warning if all are fallback
    if [[ $fallback_count -eq ${#nodes_to_update[@]} && $fallback_count -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ WARNING:${RESET}"
        echo -e "${YELLOW}All detected nodes are configured as Fallback Nodes.${RESET}"
        echo -e "${YELLOW}Verify if normal validator nodes are expected.${RESET}"
        echo
    fi

    # Summary
    echo -e "${CYAN}${BOLD}Update Summary:${RESET}"
    echo -e "${WHITE}  • Total nodes to update: ${CYAN}${#nodes_to_update[@]}${RESET}"
    echo -e "${WHITE}  • Normal validators:     ${GREEN}$normal_count${RESET}"
    echo -e "${WHITE}  • Fallback nodes:        ${YELLOW}$fallback_count${RESET}"
    echo -e "${WHITE}  • Configuration source:  ${CYAN}https://backup.mainnet.klever.org/config.mainnet.108.tar.gz${RESET}"
    echo -e "${WHITE}  • Docker image:          ${CYAN}kleverapp/klever-go:latest${RESET}"
    echo

    # Confirm
    while true; do
        read -p $'\e[35mProceed with the update? (y/n): \e[0m' confirm
        if [[ "$confirm" == "y" || "$confirm" == "n" ]]; then
            break
        fi
        echo -e "${RED}Please enter 'y' or 'n'.${RESET}"
    done

    if [[ "$confirm" == "n" ]]; then
        echo -e "${YELLOW}Update cancelled.${RESET}"
        press_any_key
        return 0
    fi

    echo
    echo -e "${CYAN}${BOLD}Starting update process...${RESET}"

    # Update nodes
    local success_count=0
    local fail_count=0
    
    for node in "${nodes_to_update[@]}"; do
        local node_dir=$(echo "$node" | cut -d'|' -f1)
        local container_name=$(echo "$node" | cut -d'|' -f2)
        local rest_api_port=$(echo "$node" | cut -d'|' -f3)
        local redundancy=$(echo "$node" | cut -d'|' -f4)
        local display_name=$(echo "$node" | cut -d'|' -f5)
        
        if update_node "$node_dir" "$container_name" "$rest_api_port" "$redundancy" "$display_name"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    echo
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}Update Summary:${RESET}"
    echo -e "${GREEN}  ✓ Successfully updated: $success_count${RESET}"
    if [ $fail_count -gt 0 ]; then
        echo -e "${RED}  ✗ Failed: $fail_count${RESET}"
    fi
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"

    press_any_key
}

################################################################################
# BLS KEY EXTRACTION MODULE
################################################################################

extract_bls_key() {
    local pem_file=$1

    if [ ! -f "$pem_file" ]; then
        echo ""
        return 1
    fi

    # Extract BLS key from header: "-----BEGIN PRIVATE KEY for [BLSKEY]-----"
    local bls_key=$(grep -oP '(?<=-----BEGIN PRIVATE KEY for ).*(?=-----)' "$pem_file" 2>/dev/null)

    if [ -z "$bls_key" ]; then
        # Try alternative format with brackets
        bls_key=$(grep -oP '(?<=\[)[^\]]+(?=\])' "$pem_file" 2>/dev/null | head -1)
    fi

    echo "$bls_key"
}

display_bls_keys() {
    display_header
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}           BLS PUBLIC KEY EXTRACTION           ${RESET}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo

    local node_info=$(find_node_directories)

    if [[ -z "$node_info" ]]; then
        echo -e "${RED}No Klever nodes found.${RESET}"
        press_any_key
        return 1
    fi

    echo -e "${YELLOW}${BOLD}Info:${RESET} ${YELLOW}The BLS Public Key is required for validator registration.${RESET}"
    echo -e "${YELLOW}      Copy the key and use it when creating your validator on Klever.${RESET}"
    echo

    local found_keys=0
    local missing_keys=0

    while IFS= read -r line; do
        local node_dir=$(echo "$line" | awk '{print $1}')
        local container_name=$(echo "$line" | awk '{print $2}')
        local node_name=$(basename "$node_dir")
        local pem_file="$node_dir/config/validatorKey.pem"

        echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${WHITE}${BOLD}Node: ${CYAN}$node_name${RESET}"
        echo -e "${WHITE}Path: ${CYAN}$node_dir/config/validatorKey.pem${RESET}"
        echo

        if [ -f "$pem_file" ]; then
            local bls_key=$(extract_bls_key "$pem_file")

            if [ -n "$bls_key" ]; then
                echo -e "${GREEN}${BOLD}BLS Public Key:${RESET}"
                echo -e "${WHITE}${bls_key}${RESET}"
                ((found_keys++))
            else
                echo -e "${RED}✗ Could not extract BLS key from file.${RESET}"
                echo -e "${YELLOW}  File exists but format may be incorrect.${RESET}"
                ((missing_keys++))
            fi
        else
            echo -e "${RED}✗ validatorKey.pem not found!${RESET}"
            echo -e "${YELLOW}  Generate keys or place your validatorKey.pem in the config directory.${RESET}"
            ((missing_keys++))
        fi
        echo
    done <<< "$node_info"

    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    echo -e "${GREEN}Keys found: $found_keys${RESET}"
    if [ $missing_keys -gt 0 ]; then
        echo -e "${RED}Missing/Invalid: $missing_keys${RESET}"
    fi
    echo
    echo -e "${YELLOW}${BOLD}Tip:${RESET} ${YELLOW}You can copy a key by selecting it with your mouse.${RESET}"

    press_any_key
}

################################################################################
# NODE MANAGEMENT MODULE
################################################################################

get_container_status() {
    local container_name=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "running"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "stopped"
    else
        echo "not_found"
    fi
}

get_container_uptime() {
    local container_name=$1
    local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
    
    if [ "$status" == "running" ]; then
        local started=$(docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null)
        if [ -n "$started" ]; then
            local start_epoch=$(date -d "$started" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local diff=$((now_epoch - start_epoch))
            
            local days=$((diff / 86400))
            local hours=$(( (diff % 86400) / 3600 ))
            local minutes=$(( (diff % 3600) / 60 ))
            
            if [ $days -gt 0 ]; then
                echo "${days}d ${hours}h"
            elif [ $hours -gt 0 ]; then
                echo "${hours}h ${minutes}m"
            else
                echo "${minutes}m"
            fi
        else
            echo "unknown"
        fi
    else
        echo "-"
    fi
}

display_nodes_status() {
    local node_info=$(find_node_directories)
    
    if [[ -z "$node_info" ]]; then
        echo -e "${RED}No Klever nodes found.${RESET}"
        return 1
    fi

    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    printf "${CYAN}${BOLD}%-20s %-10s %-8s %-10s${RESET}\n" "Node Name" "Status" "Port" "Uptime"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    
    while IFS= read -r line; do
        local node_dir=$(echo "$line" | awk '{print $1}')
        local container_name=$(echo "$line" | awk '{print $2}')
        local node_name=$(basename "$node_dir")
        
        local params=$(extract_node_parameters "$container_name" "$node_name")
        local rest_api_port=$(echo "$params" | cut -d'|' -f1)
        
        local status=$(get_container_status "$container_name")
        local uptime=$(get_container_uptime "$container_name")
        
        if [ "$status" == "running" ]; then
            printf "${GREEN}%-20s${RESET} ${GREEN}%-10s${RESET} ${CYAN}%-8s${RESET} ${WHITE}%-10s${RESET}\n" \
                "$node_name" "Running" "$rest_api_port" "$uptime"
        elif [ "$status" == "stopped" ]; then
            printf "${YELLOW}%-20s${RESET} ${RED}%-10s${RESET} ${CYAN}%-8s${RESET} ${WHITE}%-10s${RESET}\n" \
                "$node_name" "Stopped" "$rest_api_port" "-"
        else
            printf "${RED}%-20s${RESET} ${RED}%-10s${RESET} ${CYAN}%-8s${RESET} ${WHITE}%-10s${RESET}\n" \
                "$node_name" "Not Found" "$rest_api_port" "-"
        fi
    done <<< "$node_info"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
}

select_nodes_interactive() {
    local action=$1
    local node_info=$(find_node_directories)
    
    if [[ -z "$node_info" ]]; then
        echo -e "${RED}No Klever nodes found.${RESET}"
        return 1
    fi

    echo
    echo -e "${CYAN}${BOLD}Available nodes:${RESET}"
    echo
    
    declare -a containers
    local index=1
    
    while IFS= read -r line; do
        local node_dir=$(echo "$line" | awk '{print $1}')
        local container_name=$(echo "$line" | awk '{print $2}')
        local node_name=$(basename "$node_dir")
        local status=$(get_container_status "$container_name")
        
        if [ "$status" == "running" ]; then
            echo -e "  ${GREEN}[$index]${RESET} ${WHITE}$node_name${RESET} (${GREEN}Running${RESET})"
        else
            echo -e "  ${YELLOW}[$index]${RESET} ${WHITE}$node_name${RESET} (${RED}Stopped${RESET})"
        fi
        
        containers+=("$container_name")
        ((index++))
    done <<< "$node_info"
    
    echo
    echo -e "  ${CYAN}[a]${RESET} All nodes"
    echo -e "  ${CYAN}[b]${RESET} Back to menu"
    echo
    
    while true; do
        read -p $'\e[35mSelect option: \e[0m' choice
        
        if [[ "$choice" == "b" ]]; then
            return 0
        elif [[ "$choice" == "a" ]]; then
            echo
            for container in "${containers[@]}"; do
                case $action in
                    "start")
                        echo -e "${CYAN}Starting $container...${RESET}"
                        docker start "$container" > /dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}✓ $container started${RESET}"
                        else
                            echo -e "${RED}✗ Failed to start $container${RESET}"
                        fi
                        ;;
                    "stop")
                        echo -e "${CYAN}Stopping $container...${RESET}"
                        docker stop "$container" > /dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}✓ $container stopped${RESET}"
                        else
                            echo -e "${RED}✗ Failed to stop $container${RESET}"
                        fi
                        ;;
                    "restart")
                        echo -e "${CYAN}Restarting $container...${RESET}"
                        docker restart "$container" > /dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}✓ $container restarted${RESET}"
                        else
                            echo -e "${RED}✗ Failed to restart $container${RESET}"
                        fi
                        ;;
                esac
            done
            echo
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#containers[@]}" ]; then
            local selected_container="${containers[$((choice-1))]}"
            echo
            case $action in
                "start")
                    echo -e "${CYAN}Starting $selected_container...${RESET}"
                    docker start "$selected_container" > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ $selected_container started successfully${RESET}"
                    else
                        echo -e "${RED}✗ Failed to start $selected_container${RESET}"
                    fi
                    ;;
                "stop")
                    echo -e "${CYAN}Stopping $selected_container...${RESET}"
                    docker stop "$selected_container" > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ $selected_container stopped successfully${RESET}"
                    else
                        echo -e "${RED}✗ Failed to stop $selected_container${RESET}"
                    fi
                    ;;
                "restart")
                    echo -e "${CYAN}Restarting $selected_container...${RESET}"
                    docker restart "$selected_container" > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ $selected_container restarted successfully${RESET}"
                    else
                        echo -e "${RED}✗ Failed to restart $selected_container${RESET}"
                    fi
                    ;;
            esac
            echo
            break
        else
            echo -e "${RED}Invalid choice. Please try again.${RESET}"
        fi
    done
}

view_node_logs() {
    local node_info=$(find_node_directories)
    
    if [[ -z "$node_info" ]]; then
        echo -e "${RED}No Klever nodes found.${RESET}"
        press_any_key
        return 1
    fi

    echo
    echo -e "${CYAN}${BOLD}Select node to view logs:${RESET}"
    echo
    
    declare -a containers
    local index=1
    
    while IFS= read -r line; do
        local node_dir=$(echo "$line" | awk '{print $1}')
        local container_name=$(echo "$line" | awk '{print $2}')
        local node_name=$(basename "$node_dir")
        local status=$(get_container_status "$container_name")
        
        if [ "$status" == "running" ]; then
            echo -e "  ${GREEN}[$index]${RESET} ${WHITE}$node_name${RESET} (${GREEN}Running${RESET})"
        else
            echo -e "  ${YELLOW}[$index]${RESET} ${WHITE}$node_name${RESET} (${RED}Stopped${RESET})"
        fi
        
        containers+=("$container_name")
        ((index++))
    done <<< "$node_info"
    
    echo
    echo -e "  ${CYAN}[b]${RESET} Back to menu"
    echo
    
    while true; do
        read -p $'\e[35mSelect node: \e[0m' choice
        
        if [[ "$choice" == "b" ]]; then
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#containers[@]}" ]; then
            local selected_container="${containers[$((choice-1))]}"
            echo
            echo -e "${CYAN}Viewing logs for $selected_container (press Ctrl+C to exit)...${RESET}"
            sleep 2
            docker logs -f --tail 100 "$selected_container"
            break
        else
            echo -e "${RED}Invalid choice. Please try again.${RESET}"
        fi
    done
}

module_manage_nodes() {
    while true; do
        display_header
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
        echo -e "${CYAN}${BOLD}              MANAGE KLEVER NODES              ${RESET}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
        echo
        
        display_nodes_status
        
        echo
        echo -e "${CYAN}${BOLD}Management Options:${RESET}"
        echo -e "  ${GREEN}[1]${RESET} Start Nodes"
        echo -e "  ${GREEN}[2]${RESET} Stop Nodes"
        echo -e "  ${GREEN}[3]${RESET} Restart Nodes"
        echo -e "  ${GREEN}[4]${RESET} View Node Logs"
        echo -e "  ${GREEN}[5]${RESET} Refresh Status"
        echo -e "  ${GREEN}[6]${RESET} Fix Node Permissions"
        echo -e "  ${GREEN}[7]${RESET} Extract BLS Public Keys"
        echo -e "  ${CYAN}[b]${RESET} Back to Main Menu"
        echo
        
        read -p $'\e[35mSelect option: \e[0m' choice
        
        case $choice in
            1)
                display_header
                echo -e "${CYAN}${BOLD}START NODES${RESET}"
                select_nodes_interactive "start"
                press_any_key
                ;;
            2)
                display_header
                echo -e "${CYAN}${BOLD}STOP NODES${RESET}"
                select_nodes_interactive "stop"
                press_any_key
                ;;
            3)
                display_header
                echo -e "${CYAN}${BOLD}RESTART NODES${RESET}"
                select_nodes_interactive "restart"
                press_any_key
                ;;
            4)
                display_header
                echo -e "${CYAN}${BOLD}VIEW NODE LOGS${RESET}"
                view_node_logs
                press_any_key
                ;;
            5)
                # Refresh - loop continues
                ;;
            6)
                display_header
                echo -e "${CYAN}${BOLD}FIX NODE PERMISSIONS${RESET}"
                echo
                local node_info=$(find_node_directories)
                if [[ -z "$node_info" ]]; then
                    echo -e "${RED}No Klever nodes found.${RESET}"
                else
                    while IFS= read -r line; do
                        local node_dir=$(echo "$line" | awk '{print $1}')
                        fix_node_permissions "$node_dir"
                        echo
                    done <<< "$node_info"
                    echo -e "${GREEN}Permission check completed for all nodes.${RESET}"
                fi
                press_any_key
                ;;
            7)
                display_bls_keys
                ;;
            b|B)
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

################################################################################
# MAIN MENU
################################################################################

main_menu() {
    while true; do
        display_header
        echo -e "${CYAN}${BOLD}Please select an option:${RESET}"
        echo
        echo -e "  ${GREEN}[1]${RESET} Create New Nodes"
        echo -e "  ${GREEN}[2]${RESET} Update Existing Nodes"
        echo -e "  ${GREEN}[3]${RESET} Manage Nodes (Start/Stop/Status)"
        echo -e "  ${RED}[4]${RESET} Exit"
        echo
        
        read -p $'\e[35mEnter your choice [1-4]: \e[0m' choice
        
        case $choice in
            1)
                module_create_nodes
                ;;
            2)
                module_update_nodes
                ;;
            3)
                module_manage_nodes
                ;;
            4)
                display_header
                echo -e "${GREEN}Thank you for using Klever Node Management Suite!${RESET}"
                echo -e "${CYAN}Created by CryptoJaeger^^${RESET}"
                echo
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-4.${RESET}"
                sleep 1
                ;;
        esac
    done
}

################################################################################
# SCRIPT ENTRY POINT
################################################################################

# Check root privileges
check_root

# Install bc for progress calculations
check_bc_installed

# Start main menu
main_menu
