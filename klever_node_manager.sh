#!/bin/bash

set -u

################################################################################
#                     Klever Node Management Suite                             #
#                      Created by CryptoJaeger^^                               #
################################################################################

VERSION="1.1.0"

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
    local steps=50
    local sleep_time
    sleep_time=$(awk "BEGIN {printf \"%.4f\", $duration / $steps}")

    echo -ne "${CYAN}${message}${RESET} "
    while [ $progress -le 100 ]; do
        local filled=$((progress * bar_length / 100))
        local empty=$((bar_length - filled))
        printf "\r${CYAN}${message}${RESET} ["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] ${progress}%%"
        progress=$((progress + 2))
        sleep "$sleep_time"
    done
    echo -e " ${GREEN}✓${RESET}"
}

# Spinner for indeterminate progress. Waits for PID and returns its exit code.
show_spinner() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0

    echo -ne "${CYAN}${message}${RESET} "
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}${message}${RESET} ${spin:$i:1}"
        sleep 0.1
    done
    wait "$pid"
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf "\r${CYAN}${message}${RESET} ${GREEN}✓${RESET}\n"
    else
        printf "\r${CYAN}${message}${RESET} ${RED}✗${RESET}\n"
    fi
    return $exit_code
}

# Wait for user
press_any_key() {
    echo
    echo -e "${YELLOW}Press any key to continue...${RESET}"
    read -n 1 -s
}

# Prompt user for y/n confirmation. Returns the answer via stdout.
confirm_yn() {
    local prompt=$1
    local answer
    while true; do
        read -p $'\e[35m'"${prompt}"$' (y/n): \e[0m' answer
        if [[ "$answer" == "y" || "$answer" == "n" ]]; then
            echo "$answer"
            return
        fi
        echo -e "${RED}Please enter 'y' or 'n'.${RESET}" >&2
    done
}

# Create a secure temporary file. Caller must clean up.
make_temp_file() {
    local prefix=${1:-klever}
    mktemp "/tmp/${prefix}_XXXXXX"
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
        curl -fsSL "https://download.docker.com/linux/$DISTRO/gpg" -o /etc/apt/keyrings/docker.asc > /dev/null 2>&1
        chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO $CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update > /dev/null 2>&1
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    ) &
    local bg_pid=$!
    show_spinner $bg_pid "Installing Docker"
    local install_result=$?

    if [ $install_result -eq 0 ]; then
        systemctl enable --now docker > /dev/null 2>&1
        if ! systemctl is-active --quiet docker; then
            echo -e "${RED}Docker service failed to start. Please check manually.${RESET}"
            exit 1
        fi
        echo -e "${GREEN}Docker installed successfully.${RESET}"

        # Add the original user to docker group
        if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
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

################################################################################
# NODE DISCOVERY FUNCTIONS
################################################################################

# Find all Klever node directories and containers
find_node_directories() {
    docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' | grep 'kleverapp/klever-go' | while read -r container_id image container_name; do
        local dirs
        dirs=$(docker inspect "$container_id" 2>/dev/null | jq -r '.[].Mounts[] | select(.Destination | startswith("/opt/klever-blockchain")) | .Source' 2>/dev/null | while read -r dir; do dirname "$dir"; done | sort -u)
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
    local node_name
    node_name=$(basename "$node_dir")

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

    # Verify permissions
    local all_correct=true
    for subdir in config db logs wallet; do
        if [ -d "$node_dir/$subdir" ]; then
            local owner
            owner=$(stat -c '%u:%g' "$node_dir/$subdir" 2>/dev/null)
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

# Docker image tag (default: latest, can be overridden per session)
DOCKER_IMAGE_TAG="latest"

# Prompt user to select a Docker image tag from available tags
select_docker_image_tag() {
    echo -e "${CYAN}Fetching available image tags...${RESET}"
    local tags_json
    tags_json=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://hub.docker.com/v2/repositories/kleverapp/klever-go/tags/?page_size=100&ordering=last_updated" 2>/dev/null)

    local tags=()
    if [[ -n "$tags_json" ]]; then
        local parsed
        parsed=$(echo "$tags_json" | jq -r '.results[].name' 2>/dev/null)
        if [[ -n "$parsed" ]]; then
            while IFS= read -r tag; do
                # Skip dev, testnet, devnet, alpine, and val-only images
                [[ "$tag" == dev-* ]] && continue
                [[ "$tag" == *-testnet ]] && continue
                [[ "$tag" == *-devnet ]] && continue
                [[ "$tag" == val-* ]] && continue
                [[ "$tag" == alpine-* ]] && continue
                tags+=("$tag")
                # Limit to 15 filtered results
                [[ ${#tags[@]} -ge 15 ]] && break
            done <<< "$parsed"
        fi
    fi

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Could not fetch tags. Using default.${RESET}"
        echo -ne "${YELLOW}Docker image tag ${WHITE}[latest]${YELLOW}: ${RESET}"
        local input_tag
        read -r input_tag
        if [[ -n "$input_tag" ]]; then
            DOCKER_IMAGE_TAG="$input_tag"
        else
            DOCKER_IMAGE_TAG="latest"
        fi
        return
    fi

    echo
    echo -e "${WHITE}${BOLD}Available image tags:${RESET}"
    echo
    local i=1
    for tag in "${tags[@]}"; do
        if [[ "$tag" == "latest" ]]; then
            printf "  ${GREEN}${BOLD}[%2d] %-30s (default)${RESET}\n" "$i" "$tag"
        else
            printf "  ${WHITE}[%2d] ${CYAN}%-30s${RESET}\n" "$i" "$tag"
        fi
        ((i++))
    done
    echo
    echo -ne "${YELLOW}Select tag number or type custom tag ${WHITE}[latest]${YELLOW}: ${RESET}"
    local selection
    read -r selection

    if [[ -z "$selection" ]]; then
        DOCKER_IMAGE_TAG="latest"
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#tags[@]} ]]; then
        DOCKER_IMAGE_TAG="${tags[$((selection - 1))]}"
    else
        DOCKER_IMAGE_TAG="$selection"
    fi

    echo -e "${GREEN}Selected: kleverapp/klever-go:${DOCKER_IMAGE_TAG}${RESET}"
}

# Start a Klever node Docker container
start_node_container() {
    local container_name=$1
    local node_dir=$2
    local rest_api_port=$3
    local display_name=$4
    local redundancy=${5:-}

    docker run -d \
        --restart unless-stopped \
        --user "999:999" \
        --name "$container_name" \
        -v "$node_dir/config:/opt/klever-blockchain/config/node" \
        -v "$node_dir/db:/opt/klever-blockchain/db" \
        -v "$node_dir/logs:/opt/klever-blockchain/logs" \
        -v "$node_dir/wallet:/opt/klever-blockchain/wallet" \
        --network=host \
        --entrypoint=/usr/local/bin/validator \
        "kleverapp/klever-go:${DOCKER_IMAGE_TAG}" \
        '--log-save' '--use-log-view' "--rest-api-interface=0.0.0.0:$rest_api_port" \
        "--display-name=$display_name" '--start-in-epoch' $redundancy > /dev/null 2>&1
}

# Find next available node number and port
find_next_available_node() {
    local base_path=$1
    local existing_nodes
    existing_nodes=$(find_node_directories 2>/dev/null)

    # Find highest existing node number
    local max_node_num=0
    local max_port=8079

    if [[ -n "$existing_nodes" ]]; then
        while IFS= read -r line; do
            local node_dir
            node_dir=$(echo "$line" | awk '{print $1}')
            local container_name
            container_name=$(echo "$line" | awk '{print $2}')
            local node_name
            node_name=$(basename "$node_dir")

            # Extract node number
            if [[ $node_name =~ node([0-9]+) ]]; then
                local node_num=${BASH_REMATCH[1]}
                if [ "$node_num" -gt "$max_node_num" ]; then
                    max_node_num=$node_num
                fi
            fi

            # Extract port
            local params
            params=$(extract_node_parameters "$container_name" "$node_name")
            local port
            port=$(echo "$params" | cut -d'|' -f1)
            if [ "$port" -gt "$max_port" ]; then
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
    local start_port=$5
    local node_name="node$node_number"
    local rest_api_port=${start_port:-$((8080 + node_number - 1))}
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
    if ! check_port "$rest_api_port"; then
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

    # Define cleanup for partial failures after directory creation
    cleanup_failed_node() {
        echo -e "${YELLOW}  Cleaning up partial installation...${RESET}"
        rm -rf "$node_path"
    }

    # Fix permissions
    fix_node_permissions "$node_path"

    # Download configuration
    echo -e "${CYAN}  Downloading configuration...${RESET}"
    local config_downloaded=false

    # Try primary source: official Klever backup
    local tmp_file
    tmp_file=$(make_temp_file "config_${node_name}")

    if curl -s -f -o "$tmp_file" "https://backup.mainnet.klever.org/config.mainnet.108.tar.gz" 2>/dev/null; then
        pushd "$node_path/config" > /dev/null || return 1
        tar -xzf "$tmp_file" --strip-components=1 2>/dev/null
        local extract_status=$?
        popd > /dev/null || true
        rm -f "$tmp_file"
        if [ $extract_status -eq 0 ]; then
            config_downloaded=true
            echo -e "${GREEN}  ✓ Configuration downloaded from primary source${RESET}"
        fi
    else
        rm -f "$tmp_file"
    fi

    # Fallback: individual files from GitHub (transparent & auditable)
    if [ "$config_downloaded" = false ]; then
        echo -e "${YELLOW}  Primary source unavailable, trying GitHub fallback...${RESET}"
        local github_base="https://raw.githubusercontent.com/klever-io/klever-go/develop/config/node"
        local config_files=("api.yaml" "config.yaml" "enableEpochs.yaml" "external.yaml" "gasScheduleV1.yaml" "genesis.json" "nodesSetup.json")
        local all_ok=true

        for cfg_file in "${config_files[@]}"; do
            if ! curl -s -f -o "$node_path/config/$cfg_file" "$github_base/$cfg_file" 2>/dev/null; then
                all_ok=false
                break
            fi
        done

        if [ "$all_ok" = true ]; then
            config_downloaded=true
            echo -e "${GREEN}  ✓ Configuration downloaded from GitHub${RESET}"
        fi
    fi

    if [ "$config_downloaded" = false ]; then
        echo -e "${RED}✗ Could not download configuration files.${RESET}"
        cleanup_failed_node
        return 1
    fi

    # Generate validator keys if needed
    if [[ "$generate_keys" == "y" ]]; then
        echo -e "${CYAN}  Generating validator keys...${RESET}"
        docker run -it --rm -v "$node_path/config:/opt/klever-blockchain" \
            --user "999:999" \
            --entrypoint='' "kleverapp/klever-go:${DOCKER_IMAGE_TAG}" keygenerator > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ Failed to generate validator key.${RESET}"
            cleanup_failed_node
            return 1
        fi
        echo -e "${GREEN}  ✓ Validator keys generated${RESET}"
    fi

    # Start Docker container
    echo -e "${CYAN}  Starting Docker container...${RESET}"
    if start_node_container "klever-$node_name" "$node_path" "$rest_api_port" "$node_name" "$redundancy"; then
        echo -e "${GREEN}  ✓ Container started successfully${RESET}"
        echo -e "${GREEN}${BOLD}✓ Node $node_name created successfully!${RESET}"
        return 0
    else
        echo -e "${RED}✗ Failed to start Docker container.${RESET}"
        cleanup_failed_node
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
    local existing_nodes
    existing_nodes=$(find_node_directories 2>/dev/null)

    if [[ -n "$existing_nodes" ]]; then
        echo -e "${YELLOW}${BOLD}Existing nodes detected:${RESET}"
        echo

        declare -a used_ports
        declare -a existing_node_names

        while IFS= read -r line; do
            local node_dir
            node_dir=$(echo "$line" | awk '{print $1}')
            local container_name
            container_name=$(echo "$line" | awk '{print $2}')
            local node_name
            node_name=$(basename "$node_dir")

            local params
            params=$(extract_node_parameters "$container_name" "$node_name")
            local rest_api_port
            rest_api_port=$(echo "$params" | cut -d'|' -f1)
            local redundancy
            redundancy=$(echo "$params" | cut -d'|' -f2)
            local status
            status=$(get_container_status "$container_name")

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
            if [ "$port" -gt "$max_port" ]; then
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

        local continue_create
        continue_create=$(confirm_yn "Do you want to continue creating additional nodes?")

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

    # Select Docker image tag
    select_docker_image_tag
    echo

    # Pull Docker image
    echo -e "${CYAN}Pulling Docker image...${RESET}"
    (docker pull "kleverapp/klever-go:${DOCKER_IMAGE_TAG}" > /dev/null 2>&1) &
    show_spinner $! "Pulling kleverapp/klever-go:${DOCKER_IMAGE_TAG}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to pull Docker image kleverapp/klever-go:${DOCKER_IMAGE_TAG}.${RESET}"
        press_any_key
        return 1
    fi
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

    local fallback_choice
    fallback_choice=$(confirm_yn "Are these fallback nodes?")

    local redundancy=""
    local generate_keys=""

    if [[ "$fallback_choice" == "y" ]]; then
        redundancy="--redundancy-level=1"
        generate_keys="n"
        echo -e "${CYAN}Fallback nodes will be created with redundancy level 1.${RESET}"
    else
        redundancy=""
        echo
        generate_keys=$(confirm_yn "Do you need to generate new BLS validator keys?")
    fi
    echo

    # Find next available node number and port
    local next_info
    next_info=$(find_next_available_node "$base_path")
    local next_node_num
    next_node_num=$(echo "$next_info" | cut -d'|' -f1)
    local next_port
    next_port=$(echo "$next_info" | cut -d'|' -f2)

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

    local confirm
    confirm=$(confirm_yn "Proceed with node creation?")

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

    for ((i=0; i<num_nodes; i++)); do
        local current_node_num=$((next_node_num + i))
        local current_port=$((next_port + i))
        if create_node "$current_node_num" "$base_path" "$redundancy" "$generate_keys" "$current_port"; then
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
    local node_name
    node_name=$(basename "$node_dir")

    echo
    echo -e "${CYAN}${BOLD}Updating $node_name (container: $container_name)...${RESET}"

    # Download configuration
    echo -e "${CYAN}  Downloading latest configuration...${RESET}"
    local config_downloaded=false

    # Try primary source: official Klever backup
    local tmp_file
    tmp_file=$(make_temp_file "config_update_${node_name}")

    if curl -s -f -o "$tmp_file" "https://backup.mainnet.klever.org/config.mainnet.108.tar.gz" 2>/dev/null; then
        pushd "$node_dir" > /dev/null || return 1
        tar -xzf "$tmp_file" --strip-components=1 -C ./config 2>/dev/null
        local extract_status=$?
        popd > /dev/null || true
        rm -f "$tmp_file"
        if [ $extract_status -eq 0 ]; then
            config_downloaded=true
            echo -e "${GREEN}  ✓ Configuration downloaded${RESET}"
        fi
    else
        rm -f "$tmp_file"
    fi

    # Fallback: individual files from GitHub (transparent & auditable)
    if [ "$config_downloaded" = false ]; then
        echo -e "${YELLOW}  Primary source unavailable, trying GitHub fallback...${RESET}"
        local github_base="https://raw.githubusercontent.com/klever-io/klever-go/develop/config/node"
        local config_files=("api.yaml" "config.yaml" "enableEpochs.yaml" "external.yaml" "gasScheduleV1.yaml" "genesis.json" "nodesSetup.json")
        local all_ok=true

        for cfg_file in "${config_files[@]}"; do
            if ! curl -s -f -o "$node_dir/config/$cfg_file" "$github_base/$cfg_file" 2>/dev/null; then
                all_ok=false
                break
            fi
        done

        if [ "$all_ok" = true ]; then
            config_downloaded=true
            echo -e "${GREEN}  ✓ Configuration downloaded from GitHub${RESET}"
        fi
    fi

    if [ "$config_downloaded" = false ]; then
        echo -e "${RED}✗ Failed to download configuration files.${RESET}"
        return 1
    fi

    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${CYAN}  Stopping container...${RESET}"
        docker stop "$container_name" > /dev/null 2>&1
        echo -e "${GREEN}  ✓ Container stopped${RESET}"

        echo -e "${CYAN}  Removing old container...${RESET}"
        docker rm "$container_name" > /dev/null 2>&1
        echo -e "${GREEN}  ✓ Container removed${RESET}"
    fi

    # Fix permissions
    fix_node_permissions "$node_dir"

    # Start new container
    echo -e "${CYAN}  Starting new container...${RESET}"
    echo -e "${CYAN}    REST API Port: ${WHITE}0.0.0.0:$rest_api_port${RESET}"
    if [[ -n "$redundancy" ]]; then
        echo -e "${CYAN}    Redundancy: ${WHITE}$redundancy${RESET}"
    else
        echo -e "${CYAN}    Redundancy: ${WHITE}None (Normal validator)${RESET}"
    fi
    echo -e "${CYAN}    Display Name: ${WHITE}$display_name${RESET}"

    if start_node_container "$container_name" "$node_dir" "$rest_api_port" "$display_name" "$redundancy"; then
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
        local node_dir
        node_dir=$(echo "$line" | awk '{print $1}')
        local container_name
        container_name=$(echo "$line" | awk '{print $2}')
        local node_name
        node_name=$(basename "$node_dir")

        local params
        params=$(extract_node_parameters "$container_name" "$node_name")
        local rest_api_port
        rest_api_port=$(echo "$params" | cut -d'|' -f1)
        local redundancy
        redundancy=$(echo "$params" | cut -d'|' -f2)
        local display_name
        display_name=$(echo "$params" | cut -d'|' -f3)

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

    # Get current running version from first node
    local first_container
    first_container=$(echo "${nodes_to_update[0]}" | cut -d'|' -f2)
    local current_version
    current_version=$(get_node_version "$first_container")
    local current_digest
    current_digest=$(docker inspect "$first_container" --format='{{.Image}}' 2>/dev/null | cut -c1-19)

    # Select Docker image tag
    select_docker_image_tag
    echo

    # Pull image to check for updates
    echo -e "${CYAN}Checking for image updates...${RESET}"
    (docker pull "kleverapp/klever-go:${DOCKER_IMAGE_TAG}" > /dev/null 2>&1) &
    show_spinner $! "Pulling kleverapp/klever-go:${DOCKER_IMAGE_TAG}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to pull Docker image kleverapp/klever-go:${DOCKER_IMAGE_TAG}.${RESET}"
        echo -e "${YELLOW}Please verify the tag exists and try again.${RESET}"
        press_any_key
        return 1
    fi
    echo

    local latest_version
    latest_version=$(docker inspect "kleverapp/klever-go:${DOCKER_IMAGE_TAG}" --format='{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null)
    if [[ -z "$latest_version" || "$latest_version" == "<no value>" ]]; then
        latest_version="unknown"
    fi
    local latest_digest
    latest_digest=$(docker inspect "kleverapp/klever-go:${DOCKER_IMAGE_TAG}" --format='{{.Id}}' 2>/dev/null | cut -c1-19)

    local image_changed="no"
    if [[ "$current_digest" != "$latest_digest" ]]; then
        image_changed="yes"
    fi

    # Summary
    echo -e "${CYAN}${BOLD}Update Summary:${RESET}"
    echo -e "${WHITE}  • Total nodes to update: ${CYAN}${#nodes_to_update[@]}${RESET}"
    echo -e "${WHITE}  • Normal validators:     ${GREEN}$normal_count${RESET}"
    echo -e "${WHITE}  • Fallback nodes:        ${YELLOW}$fallback_count${RESET}"
    echo -e "${WHITE}  • Configuration source:  ${CYAN}backup.mainnet.klever.org (fallback: klever-io/klever-go)${RESET}"
    echo -e "${WHITE}  • Docker image:          ${CYAN}kleverapp/klever-go:${DOCKER_IMAGE_TAG}${RESET}"
    echo
    echo -e "${WHITE}  • Running version:       ${CYAN}$current_version${RESET}"
    echo -e "${WHITE}  • Target version:        ${CYAN}$latest_version${RESET}"
    if [[ "$image_changed" == "yes" ]]; then
        echo -e "  ${GREEN}${BOLD}  ↑ New image available!${RESET}"
    else
        echo -e "  ${YELLOW}  ✓ Image is already up to date${RESET}"
    fi
    echo -e "${WHITE}  • Config will be refreshed from latest source${RESET}"
    echo

    # Confirm
    local confirm
    confirm=$(confirm_yn "Proceed with the update?")

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
        local node_dir
        node_dir=$(echo "$node" | cut -d'|' -f1)
        local container_name
        container_name=$(echo "$node" | cut -d'|' -f2)
        local rest_api_port
        rest_api_port=$(echo "$node" | cut -d'|' -f3)
        local redundancy
        redundancy=$(echo "$node" | cut -d'|' -f4)
        local display_name
        display_name=$(echo "$node" | cut -d'|' -f5)

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
    local bls_key
    bls_key=$(sed -n 's/.*BEGIN PRIVATE KEY for \(.*\)-----.*/\1/p' "$pem_file" 2>/dev/null | tr -d '[:space:]')

    if [ -z "$bls_key" ]; then
        # Try alternative format with brackets
        bls_key=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$pem_file" 2>/dev/null | head -1)
    fi

    echo "$bls_key"
}

display_bls_keys() {
    display_header
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}           BLS PUBLIC KEY EXTRACTION           ${RESET}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo

    local node_info
    node_info=$(find_node_directories)

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
        local node_dir
        node_dir=$(echo "$line" | awk '{print $1}')
        local container_name
        container_name=$(echo "$line" | awk '{print $2}')
        local node_name
        node_name=$(basename "$node_dir")
        local pem_file="$node_dir/config/validatorKey.pem"

        echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${WHITE}${BOLD}Node: ${CYAN}$node_name${RESET}"
        echo -e "${WHITE}Path: ${CYAN}$node_dir/config/validatorKey.pem${RESET}"
        echo

        if [ -f "$pem_file" ]; then
            local bls_key
            bls_key=$(extract_bls_key "$pem_file")

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

get_node_version() {
    local container_name=$1
    local version
    version=$(docker inspect "$container_name" --format='{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null)
    if [[ -z "$version" || "$version" == "<no value>" ]]; then
        echo "-"
    else
        echo "$version"
    fi
}

get_node_sync_status() {
    local rest_api_port=$1
    local response
    response=$(curl -s --connect-timeout 2 --max-time 3 "http://127.0.0.1:${rest_api_port}/node/status" 2>/dev/null)

    if [[ -z "$response" ]]; then
        echo "-|-"
        return
    fi

    local nonce
    nonce=$(echo "$response" | jq -r '.data.metrics.klv_nonce // empty' 2>/dev/null)
    local is_syncing
    is_syncing=$(echo "$response" | jq -r '.data.metrics.klv_is_syncing // empty' 2>/dev/null)

    if [[ -z "$nonce" ]]; then
        echo "-|-"
        return
    fi

    local sync_label
    if [[ "$is_syncing" == "0" ]]; then
        sync_label="Synced"
    else
        sync_label="Syncing"
    fi

    echo "${nonce}|${sync_label}"
}

get_container_uptime() {
    local container_name=$1
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)

    if [ "$status" == "running" ]; then
        local started
        started=$(docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null)
        if [ -n "$started" ]; then
            local start_epoch
            start_epoch=$(date -d "$started" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
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
    local node_info
    node_info=$(find_node_directories)

    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}                                      MANAGE KLEVER NODES                                        ${RESET}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════════════════════════${RESET}"

    if [[ -z "$node_info" ]]; then
        echo
        echo -e "${RED}  No Klever nodes found.${RESET}"
        echo
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════════════════════════${RESET}"
        return 1
    fi

    printf "${CYAN}${BOLD}  %-13s %-10s %-6s %-24s %-10s %-12s %-10s${RESET}\n" "Node" "Status" "Port" "Version" "Uptime" "Nonce" "Sync"
    echo -e "${CYAN}  ─────────────────────────────────────────────────────────────────────────────────────────────────${RESET}"

    while IFS= read -r line; do
        local node_dir
        node_dir=$(echo "$line" | awk '{print $1}')
        local container_name
        container_name=$(echo "$line" | awk '{print $2}')
        local node_name
        node_name=$(basename "$node_dir")

        local params
        params=$(extract_node_parameters "$container_name" "$node_name")
        local rest_api_port
        rest_api_port=$(echo "$params" | cut -d'|' -f1)

        local status
        status=$(get_container_status "$container_name")
        local uptime
        uptime=$(get_container_uptime "$container_name")
        local version
        version=$(get_node_version "$container_name")

        local nonce="--"
        local sync_label="--"

        if [ "$status" == "running" ]; then
            local sync_info
            sync_info=$(get_node_sync_status "$rest_api_port")
            nonce=$(echo "$sync_info" | cut -d'|' -f1)
            sync_label=$(echo "$sync_info" | cut -d'|' -f2)

            local sync_color="${GREEN}"
            if [ "$sync_label" == "Syncing" ]; then
                sync_color="${YELLOW}"
            elif [ "$sync_label" == "-" ]; then
                nonce="--"
                sync_label="--"
                sync_color="${WHITE}"
            fi

            printf "  ${GREEN}%-13s${RESET} ${GREEN}%-10s${RESET} ${CYAN}%-6s${RESET} ${WHITE}%-24s${RESET} ${WHITE}%-10s${RESET} ${WHITE}%-12s${RESET} ${sync_color}%-10s${RESET}\n" \
                "$node_name" "Running" "$rest_api_port" "$version" "$uptime" "$nonce" "$sync_label"
        elif [ "$status" == "stopped" ]; then
            printf "  ${YELLOW}%-13s${RESET} ${RED}%-10s${RESET} ${CYAN}%-6s${RESET} ${WHITE}%-24s${RESET} ${WHITE}%-10s${RESET} ${WHITE}%-12s${RESET} ${WHITE}%-10s${RESET}\n" \
                "$node_name" "Stopped" "$rest_api_port" "$version" "--" "--" "--"
        else
            printf "  ${RED}%-13s${RESET} ${RED}%-10s${RESET} ${CYAN}%-6s${RESET} ${WHITE}%-24s${RESET} ${WHITE}%-10s${RESET} ${WHITE}%-12s${RESET} ${WHITE}%-10s${RESET}\n" \
                "$node_name" "Not Found" "$rest_api_port" "--" "--" "--" "--"
        fi
    done <<< "$node_info"

    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════════════════════════${RESET}"
}

# Display numbered list of nodes. Populates the MENU_CONTAINERS array.
# Returns 1 if no nodes found.
MENU_CONTAINERS=()
list_nodes_menu() {
    local node_info
    node_info=$(find_node_directories)

    if [[ -z "$node_info" ]]; then
        echo -e "${RED}No Klever nodes found.${RESET}"
        return 1
    fi

    echo
    echo -e "${CYAN}${BOLD}Available nodes:${RESET}"
    echo

    MENU_CONTAINERS=()
    local index=1

    while IFS= read -r line; do
        local node_dir
        node_dir=$(echo "$line" | awk '{print $1}')
        local container_name
        container_name=$(echo "$line" | awk '{print $2}')
        local node_name
        node_name=$(basename "$node_dir")
        local status
        status=$(get_container_status "$container_name")

        if [ "$status" == "running" ]; then
            echo -e "  ${GREEN}[$index]${RESET} ${WHITE}$node_name${RESET} (${GREEN}Running${RESET})"
        else
            echo -e "  ${YELLOW}[$index]${RESET} ${WHITE}$node_name${RESET} (${RED}Stopped${RESET})"
        fi

        MENU_CONTAINERS+=("$container_name")
        ((index++))
    done <<< "$node_info"
}

select_nodes_interactive() {
    local action=$1

    if ! list_nodes_menu; then
        return 1
    fi

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
            for container in "${MENU_CONTAINERS[@]}"; do
                case $action in
                    start)   echo -e "${CYAN}Starting $container...${RESET}" ;;
                    stop)    echo -e "${CYAN}Stopping $container...${RESET}" ;;
                    restart) echo -e "${CYAN}Restarting $container...${RESET}" ;;
                esac
                if docker "$action" "$container" > /dev/null 2>&1; then
                    case $action in
                        start)   echo -e "${GREEN}✓ $container started${RESET}" ;;
                        stop)    echo -e "${GREEN}✓ $container stopped${RESET}" ;;
                        restart) echo -e "${GREEN}✓ $container restarted${RESET}" ;;
                    esac
                else
                    echo -e "${RED}✗ Failed to $action $container${RESET}"
                fi
            done
            echo
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MENU_CONTAINERS[@]}" ]; then
            local selected_container="${MENU_CONTAINERS[$((choice-1))]}"
            echo
            case $action in
                start)   echo -e "${CYAN}Starting $selected_container...${RESET}" ;;
                stop)    echo -e "${CYAN}Stopping $selected_container...${RESET}" ;;
                restart) echo -e "${CYAN}Restarting $selected_container...${RESET}" ;;
            esac
            if docker "$action" "$selected_container" > /dev/null 2>&1; then
                case $action in
                    start)   echo -e "${GREEN}✓ $selected_container started successfully${RESET}" ;;
                    stop)    echo -e "${GREEN}✓ $selected_container stopped successfully${RESET}" ;;
                    restart) echo -e "${GREEN}✓ $selected_container restarted successfully${RESET}" ;;
                esac
            else
                echo -e "${RED}✗ Failed to $action $selected_container${RESET}"
            fi
            echo
            break
        else
            echo -e "${RED}Invalid choice. Please try again.${RESET}"
        fi
    done
}

view_node_logs() {
    if ! list_nodes_menu; then
        press_any_key
        return 1
    fi

    echo
    echo -e "  ${CYAN}[b]${RESET} Back to menu"
    echo

    while true; do
        read -p $'\e[35mSelect node: \e[0m' choice

        if [[ "$choice" == "b" ]]; then
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MENU_CONTAINERS[@]}" ]; then
            local selected_container="${MENU_CONTAINERS[$((choice-1))]}"
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

        display_nodes_status

        echo
        echo -e "${CYAN}${BOLD}Options:${RESET}"
        echo -e "  ${GREEN}[1]${RESET} Start Nodes          ${GREEN}[5]${RESET} Refresh Status"
        echo -e "  ${GREEN}[2]${RESET} Stop Nodes           ${GREEN}[6]${RESET} Fix Node Permissions"
        echo -e "  ${GREEN}[3]${RESET} Restart Nodes        ${GREEN}[7]${RESET} Extract BLS Public Keys"
        echo -e "  ${GREEN}[4]${RESET} View Node Logs       ${CYAN}[b]${RESET} Back to Main Menu"
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
                local node_info
                node_info=$(find_node_directories)
                if [[ -z "$node_info" ]]; then
                    echo -e "${RED}No Klever nodes found.${RESET}"
                else
                    while IFS= read -r line; do
                        local node_dir
                        node_dir=$(echo "$line" | awk '{print $1}')
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

# Handle command-line arguments
case "${1:-}" in
    --help|-h)
        echo "Klever Node Management Suite v${VERSION}"
        echo ""
        echo "Usage: sudo $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --version, -v    Show version number"
        echo ""
        echo "One-line install:"
        echo "  curl -sSL https://raw.githubusercontent.com/CTJaeger/KleverNodeManagement/main/klever_node_manager.sh | sudo bash"
        echo ""
        echo "This script must be run as root or with sudo."
        exit 0
        ;;
    --version|-v)
        echo "Klever Node Management Suite v${VERSION}"
        exit 0
        ;;
esac

# When piped via stdin (curl | bash), redirect stdin to the terminal so
# interactive prompts work. Only do this when /dev/tty is available and
# the script itself is being read from stdin (i.e., not a regular file).
if [ ! -t 0 ] && [ -c /dev/tty ] && [ -z "${BASH_SOURCE[0]:-}" ]; then
    exec </dev/tty
fi

# Check root privileges
check_root

# Ensure jq is available (required for node discovery)
check_jq_installed

# Start main menu
main_menu
