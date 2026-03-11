# Klever Node Management Suite

[![CI](https://github.com/CTJaeger/KleverNodeManagement/actions/workflows/ci.yml/badge.svg)](https://github.com/CTJaeger/KleverNodeManagement/actions/workflows/ci.yml)

**An all-in-one solution for managing Klever validator nodes**

---

## ⚙️ Requirements

**Supported Systems:** Ubuntu 20.04+, Debian 10+

**Requirements:**

* Docker (automatically installed if missing)
* jq (automatically installed if missing)
* Root/sudo access

---

## 📋 Overview

This script provides a unified interface for creating, updating, and managing Klever validator nodes on Ubuntu/Debian systems. It automates the entire node lifecycle with safety checks and beginner-friendly prompts.

### Key Features

* **Create Nodes**: Automated setup with intelligent port assignment
* **Update Nodes**: Safe updates preserving all blockchain data, with version comparison
* **Manage Nodes**: Start, stop, restart, and monitor node status
* **Monitoring Dashboard**: Real-time view of Version, Nonce, and Sync status per node
* **Docker Image Tag Selector**: Choose specific Docker image versions from Docker Hub
* **Extract BLS Keys**: Easy extraction of BLS Public Keys for validator registration
* **Safety First**: Automatic detection of existing nodes to prevent data loss
* **Smart Detection**: Finds next available node numbers and ports automatically
* **CLI Flags**: `--help` and `--version` for quick info
* **CI/CD**: Automated ShellCheck and syntax validation via GitHub Actions

---

## 🚀 Installation

### Quick Install (One Command)

```bash
curl -sSL https://raw.githubusercontent.com/CTJaeger/KleverNodeManagement/main/klever_node_manager.sh | sudo bash
```

### Manual Install

**Step 1: Download the Script**

```bash
wget https://raw.githubusercontent.com/CTJaeger/KleverNodeManagement/main/klever_node_manager.sh
```

**Step 2: Make Executable**

```bash
chmod +x klever_node_manager.sh
```

**Step 3: Run the Script**

```bash
sudo ./klever_node_manager.sh
```

### CLI Options

```bash
sudo ./klever_node_manager.sh --help      # Show help message
sudo ./klever_node_manager.sh --version   # Show version number
```

---

## 📖 Usage Guide

### Main Menu

When you start the script, you'll see:

```
************************************************
*        Klever Node Management Suite          *
*           Created by CryptoJaeger^^          *
************************************************

Please select an option:

  [1] Create New Nodes
  [2] Update Existing Nodes
  [3] Manage Nodes (Start/Stop/Status)
  [4] Exit

Enter your choice [1-4]: _
```

---

## 1️⃣ Creating New Nodes

### Docker Image Tag Selection

When creating nodes, you can choose which Docker image version to use:

```
Fetching available image tags...

Available image tags:

  [ 1] latest                         (default)
  [ 2] v0.8.2
  [ 3] v0.8.1
  ...

Select tag number or type custom tag [latest]: _
```

The script fetches available tags directly from Docker Hub, filtering out dev/testnet/devnet images.

### Scenario: First Installation (No Existing Nodes)

**Step-by-step example:**

```
Select option: 1

═══════════════════════════════════════════════
           CREATE NEW KLEVER NODES
═══════════════════════════════════════════════

Checking for existing Klever nodes...
No existing nodes found. You can create new nodes.

Enter installation directory (default: /opt): /opt
Installation directory: /opt

Docker is already installed.

Fetching available image tags...
[... tag selection ...]

How many nodes do you want to create? 3

Important: Fallback nodes vs. Normal nodes
  • Normal nodes: Active validators (--redundancy-level not set)
  • Fallback nodes: Backup validators (--redundancy-level=1)

Are these fallback nodes? (y/n): n

Do you need to generate new BLS validator keys? (y/n): y

Summary:
  • Installation path: /opt
  • Number of nodes: 3
  • Node type: Normal (active validator)
  • Docker image: kleverapp/klever-go:latest
  • Generate new keys: Yes
  • Node names: node1 - node3
  • REST API ports: 8080 - 8082

Proceed with node creation? (y/n): y

Creating nodes...

Creating node1...
  Creating directory structure...
  ✓ Directories created
Fixing permissions for node1...
  ✓ config permissions correct (999:999)
  ✓ db permissions correct (999:999)
  ✓ logs permissions correct (999:999)
  ✓ wallet permissions correct (999:999)
All permissions set correctly for node1.
  Downloading configuration...
  ✓ Configuration downloaded from primary source
  Extracting configuration...
  ✓ Configuration extracted
  Generating validator keys...
  ✓ Validator keys generated
  Starting Docker container...
  ✓ Container started successfully
✓ Node node1 created successfully!

[... similar output for node2 and node3 ...]

═══════════════════════════════════════════════
Node Creation Summary:
  ✓ Successfully created: 3
═══════════════════════════════════════════════

⚠ IMPORTANT:
New 'validatorKey.pem' files have been generated in each node's config directory.
Please ensure these keys are backed up securely!
```

### Scenario: Adding More Nodes (Existing Nodes Present)

If you already have nodes running, the script detects them:

```
Checking for existing Klever nodes...
Existing nodes detected:

  • node1 - Port: 8080 - Status: Running
  • node2 - Port: 8081 - Status: Running
  • node3 - Port: 8082 - Status: Running

Used ports: 8080 8081 8082
Existing node names: node1 node2 node3

New nodes will automatically use the next available ports starting from 8083.

Do you want to continue creating additional nodes? (y/n): y
```

**Important Notes:**

* **Normal Nodes**: Active validators participating in consensus. Generate new BLS keys.
* **Fallback Nodes**: Backup validators with `--redundancy-level=1`. Use the SAME BLS keys as your main nodes.
* The script automatically assigns the next available node numbers and ports.
* If a directory already exists, that node number is skipped.

---

## 2️⃣ Updating Existing Nodes

This option updates all your nodes to the latest Klever configuration and Docker image. The update flow includes **version comparison** so you can see whether an update is actually available before proceeding.

**Example update session:**

```
Select option: 2

═══════════════════════════════════════════════
         UPDATE EXISTING KLEVER NODES
═══════════════════════════════════════════════

Searching for Klever nodes...
Found Klever nodes:

Node: node1
  Path:          /opt/node1
  Container:     klever-node1
  REST API Port: 8080
  Type:          Normal Validator

[... similar output for other nodes ...]

Fetching available image tags...
[... tag selection ...]

Checking for image updates...
Pulling kleverapp/klever-go:latest ✓

Update Summary:
  • Total nodes to update: 3
  • Normal validators:     2
  • Fallback nodes:        1
  • Configuration source:  backup.mainnet.klever.org (fallback: klever-io/klever-go)
  • Docker image:          kleverapp/klever-go:latest

  • Running version:       v0.8.1
  • Target version:        v0.8.2
    ↑ New image available!
  • Config will be refreshed from latest source

Proceed with the update? (y/n): y

[... update process for each node ...]

═══════════════════════════════════════════════
Update Summary:
  ✓ Successfully updated: 3
═══════════════════════════════════════════════
```

**What Gets Updated:**

* Configuration files in `/config/` directory
* Docker image to selected version
* Container restart with preserved settings

**What Is NOT Changed:**

* Your blockchain database (`/db/`)
* Your wallet data (`/wallet/`)
* Your validator keys (`validatorKey.pem`)
* Your logs (`/logs/`)
* Port assignments
* Redundancy settings
* Display names

---

## 3️⃣ Managing Nodes

This menu provides tools for daily node management with a **real-time monitoring dashboard**.

### Monitoring Dashboard

The status overview shows **Version**, **Nonce**, and **Sync** status for each node:

```
Select option: 3

══════════════════════════════════════════════════════════════════════════════
                              MANAGE KLEVER NODES
═══════════════════════════════════════════════════════════════════════════════

  Node          Status     Port   Version                  Uptime     Nonce        Sync
  ─────────────────────────────────────────────────────────────────────────────────────
  node1         Running    8080   v0.8.2                   5d 12h     12345678     Synced
  node2         Running    8081   v0.8.2                   5d 12h     12345670     Syncing
  node3         Stopped    8082   v0.8.2                   --         --           --
  node4         Running    8083   v0.8.2                   2h 34m     12345678     Synced

Options:
  [1] Start Nodes          [5] Refresh Status
  [2] Stop Nodes           [6] Fix Node Permissions
  [3] Restart Nodes        [7] Extract BLS Public Keys
  [4] View Node Logs       [b] Back to Main Menu

Select option: _
```

* **Version**: Docker image version the node is running
* **Nonce**: Current block nonce (retrieved via node REST API)
* **Sync**: Shows "Synced" or "Syncing" based on the node's sync status

### Starting Nodes

```
Select option: 1

START NODES

Available nodes:

  [1] node1 (Running)
  [2] node2 (Running)
  [3] node3 (Stopped)

Options:
  [a] All nodes
  [1-3] Select specific node
  [b] Back to menu

Select option: 3

Starting klever-node3...
✓ klever-node3 started successfully
```

### Viewing Logs

```
Select option: 4

VIEW NODE LOGS

Select node to view logs:

  [1] node1 (Running)
  [2] node2 (Running)
  [3] node3 (Running)

  [b] Back to menu

Select node: 1

Viewing logs for klever-node1 (press Ctrl+C to exit)...
```

### Fixing Permissions

If you encounter permission issues, use option 6 to automatically fix ownership to `999:999` for all node directories.

### Extract BLS Public Keys

```
Select option: 7

═══════════════════════════════════════════════
           BLS PUBLIC KEY EXTRACTION
═══════════════════════════════════════════════

Info: The BLS Public Key is required for validator registration.
      Copy the key and use it when creating your validator on Klever.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Node: node1
Path: /opt/node1/config/validatorKey.pem

BLS Public Key:
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Keys found: 1

Tip: You can copy a key by selecting it with your mouse.
```

---

## 🔧 Important Notes

### BLS Validator Keys

**For Normal Validators:**

* Generate new keys when creating nodes (script option)
* OR manually place `validatorKey.pem` in `/opt/nodeX/config/`
* After placing keys manually: `docker restart klever-nodeX`

**For Fallback Nodes:**

* Use the SAME `validatorKey.pem` as your main validator
* Copy the key to each fallback node's config directory
* Must restart container after placing the key

### Permissions

All node directories require user `999:999`:

* `/opt/nodeX/config/` → 999:999
* `/opt/nodeX/db/` → 999:999
* `/opt/nodeX/logs/` → 999:999
* `/opt/nodeX/wallet/` → 999:999

The script sets these automatically during creation and updates.

### Port Assignment

* Default ports start at 8080
* Each node gets the next available port (8080, 8081, 8082, …)
* Script automatically detects used ports
* If a port is in use, that node creation is skipped

### Directory Protection

The script will NOT overwrite existing node directories:

* If `/opt/node1/` exists → node1 creation is skipped
* Create with a different node number instead
* Or remove/backup the old directory first

---

## 🐛 Troubleshooting

### "Permission denied"

Script must be run as root:

```bash
sudo ./klever_node_manager.sh
```

### Node Won't Start

1. Check logs: `docker logs klever-nodeX`
2. Verify permissions: Use option 3 → Fix Node Permissions
3. Check if validatorKey.pem is present: `ls -la /opt/nodeX/config/`

### Port Already in Use

The script detects this automatically and skips that node. To fix:

```bash
# Find what's using the port
sudo ss -tuln | grep :8080

# Stop the conflicting service or use a different port
```

---

## 📞 Useful Commands

```bash
# View all running containers
docker ps

# View all containers (including stopped)
docker ps -a

# Stop a node
docker stop klever-node1

# Start a node
docker start klever-node1

# Restart a node
docker restart klever-node1

# View live logs (last 100 lines)
docker logs -f --tail 100 klever-node1

# Check node directory contents
ls -la /opt/node1/

# Check permissions
ls -la /opt/node1/config/

# Script version
sudo ./klever_node_manager.sh --version
```

---

## 📊 Function Overview

| Function | Description |
|----|----|
| **Create Nodes** | Creates new validator nodes with automatic setup, key generation, tag selection, and smart port assignment |
| **Update Nodes** | Updates configuration and Docker image with version comparison, preserving all blockchain data and settings |
| **Start Nodes** | Starts one or all stopped nodes |
| **Stop Nodes** | Safely stops one or all running nodes |
| **Restart Nodes** | Restarts one or all nodes (useful after config changes) |
| **View Logs** | Real-time log viewer for debugging and monitoring |
| **Monitoring Dashboard** | Shows all nodes with status, port, version, uptime, nonce, and sync status |
| **Fix Permissions** | Repairs directory permissions (999:999) for all node folders |
| **Extract BLS Keys** | Displays BLS Public Keys for each node (needed for validator registration) |

---

## 🔄 Changelog

### v1.1.0 — 03/11/2026

* **Docker Image Tag Selector**: Choose specific image versions from Docker Hub when creating or updating nodes
* **Monitoring Dashboard**: Enhanced status view with Version, Nonce, and Sync columns (queries node REST API)
* **Version Comparison**: Update flow now shows running vs. target version and whether a new image is available
* **CLI Flags**: Added `--help` and `--version` command-line options
* **curl | bash Support**: Script works correctly when piped via `curl | sudo bash`
* **Security Hardening**: `set -u` for undefined variable detection, secure temp files with `mktemp`
* **CI Pipeline**: GitHub Actions workflow with ShellCheck and syntax validation
* **Code Quality**: Improved helper functions (`confirm_yn`, `make_temp_file`, `list_nodes_menu`)

### v1.0.0 — 12/20/2024

* Initial release
* Create, update, and manage Klever validator nodes
* BLS Public Key extraction
* Automatic dependency installation (Docker, jq, bc)
* Smart port and node number assignment

---

For questions or issues, please [open an issue](https://github.com/CTJaeger/KleverNodeManagement/issues).
