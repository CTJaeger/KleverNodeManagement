# Klever Node Management Suite

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
* **Update Nodes**: Safe updates preserving all blockchain data
* **Manage Nodes**: Start, stop, restart, and monitor node status
* **Extract BLS Keys**: Easy extraction of BLS Public Keys for validator registration
* **Safety First**: Automatic detection of existing nodes to prevent data loss
* **Smart Detection**: Finds next available node numbers and ports automatically

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

Pulling latest Docker image...
Pulling kleverapp/klever-go:latest ✓

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

Creating node2...
  [... similar output ...]
✓ Node node2 created successfully!

Creating node3...
  [... similar output ...]
✓ Node node3 created successfully!

═══════════════════════════════════════════════
Node Creation Summary:
  ✓ Successfully created: 3
═══════════════════════════════════════════════

⚠ IMPORTANT:
New 'validatorKey.pem' files have been generated in each node's config directory.
Please ensure these keys are backed up securely!

Node Management Commands:
  • Stop a node:  docker stop klever-node<number>
  • Start a node: docker start klever-node<number>
  • View logs:    docker logs -f --tail 50 klever-node<number>

Press any key to continue...
```

### Scenario: Adding More Nodes (Existing Nodes Present)

If you already have nodes running, the script detects them:

```
Select option: 1

Checking for existing Klever nodes...
Existing nodes detected:

  • node1 - Port: 8080 - Status: Running
  • node2 - Port: 8081 - Status: Running
  • node3 - Port: 8082 - Status: Running

Used ports: 8080 8081 8082
Existing node names: node1 node2 node3

New nodes will automatically use the next available ports starting from 8083.

Do you want to continue creating additional nodes? (y/n): y

Enter installation directory (default: /opt): /opt
Installation directory: /opt

How many nodes do you want to create? 2

Are these fallback nodes? (y/n): y

Summary:
  • Installation path: /opt
  • Number of nodes: 2
  • Node type: Fallback (redundancy-level=1)
  • Generate new keys: No
  • Node names: node4 - node5
  • REST API ports: 8083 - 8084

Proceed with node creation? (y/n): y

[... creates node4 and node5 ...]

⚠ IMPORTANT:
Please ensure the 'validatorKey.pem' file is placed in each fallback node's config directory.
After placing the key, restart the node with docker restart klever-node4
```

**Important Notes:**

* **Normal Nodes**: Active validators participating in consensus. Generate new BLS keys.
* **Fallback Nodes**: Backup validators with `--redundancy-level=1`. Use the SAME BLS keys as your main nodes.
* The script automatically assigns the next available node numbers and ports.
* If a directory already exists, that node number is skipped.

---

## 2️⃣ Updating Existing Nodes

This option updates all your nodes to the latest Klever configuration and Docker image.

**Example update session:**

```
Select option: 2

═══════════════════════════════════════════════
         UPDATE EXISTING KLEVER NODES
═══════════════════════════════════════════════

jq is already installed.

Searching for Klever nodes...
Found Klever nodes:

Node: node1
  Path:          /opt/node1
  Container:     klever-node1
  REST API Port: 8080
  Type:          Normal Validator
  Display Name:  node1

Node: node2
  Path:          /opt/node2
  Container:     klever-node2
  REST API Port: 8081
  Type:          Fallback Node (redundancy-level=1)
  Display Name:  node2

Node: node3
  Path:          /opt/node3
  Container:     klever-node3
  REST API Port: 8082
  Type:          Normal Validator
  Display Name:  node3

Update Summary:
  • Total nodes to update: 3
  • Normal validators:     2
  • Fallback nodes:        1
  • Configuration source:  https://backup.mainnet.klever.org/config.mainnet.108.tar.gz
  • Docker image:          kleverapp/klever-go:latest

Proceed with the update? (y/n): y

Starting update process...

Updating node1 (container: klever-node1)...
  Downloading latest configuration...
  ✓ Configuration downloaded
  Extracting configuration...
  ✓ Configuration extracted
  Stopping container...
  ✓ Container stopped
  Removing old container...
  ✓ Container removed
Fixing permissions for node1...
  ✓ config permissions correct (999:999)
  ✓ db permissions correct (999:999)
  ✓ logs permissions correct (999:999)
  ✓ wallet permissions correct (999:999)
All permissions set correctly for node1.
  Pulling latest Docker image...
  Pulling kleverapp/klever-go:latest ✓
  Starting new container with parameters:
    REST API Port: 0.0.0.0:8080
    Redundancy Level: None (Normal validator)
    Display Name: node1
  ✓ Container started
✓ Node node1 updated successfully!

[... similar output for node2 and node3 ...]

═══════════════════════════════════════════════
Update Summary:
  ✓ Successfully updated: 3
═══════════════════════════════════════════════

Press any key to continue...
```

**What Gets Updated:**

* Configuration files in `/config/` directory
* Docker image to latest version
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

This menu provides tools for daily node management.

### Status Overview

```
Select option: 3

═══════════════════════════════════════════════
              MANAGE KLEVER NODES
═══════════════════════════════════════════════

═══════════════════════════════════════════════════════════════
Node Name            Status     Port     Uptime
═══════════════════════════════════════════════════════════════
node1                Running    8080     5d 12h
node2                Running    8081     5d 12h
node3                Stopped    8082     -
node4                Running    8083     2h 34m
node5                Running    8084     2h 34m
═══════════════════════════════════════════════════════════════

Management Options:
  [1] Start Nodes
  [2] Stop Nodes
  [3] Restart Nodes
  [4] View Node Logs
  [5] Refresh Status
  [6] Fix Node Permissions
  [7] Extract BLS Public Keys
  [b] Back to Main Menu

Select option: _
```

### Starting Nodes

```
Select option: 1

START NODES

Available nodes:

  [1] node1 (Running)
  [2] node2 (Running)
  [3] node3 (Stopped)
  [4] node4 (Running)
  [5] node5 (Running)

Options:
  [a] All nodes
  [1-5] Select specific node
  [b] Back to menu

Select option: 3

Starting klever-node3...
✓ klever-node3 started successfully

Press any key to continue...
```

### Viewing Logs

```
Select option: 4

VIEW NODE LOGS

Select node to view logs:

  [1] node1 (Running)
  [2] node2 (Running)
  [3] node3 (Running)
  [4] node4 (Running)
  [5] node5 (Running)

  [b] Back to menu

Select node: 1

Viewing logs for klever-node1 (press Ctrl+C to exit)...

[LOG OUTPUT - Live streaming]
INFO[2025-11-06 15:23:45] Block #12345 processed
INFO[2025-11-06 15:23:46] Consensus round completed
...
```

### Fixing Permissions

If you encounter permission issues:

```
Select option: 6

FIX NODE PERMISSIONS

Fixing permissions for node1...
  ✓ config permissions correct (999:999)
  ✓ db permissions correct (999:999)
  ✓ logs permissions correct (999:999)
  ✓ wallet permissions correct (999:999)
All permissions set correctly for node1.

Fixing permissions for node2...
  ✓ config permissions correct (999:999)
  ✓ db permissions correct (999:999)
  ✓ logs permissions correct (999:999)
  ✓ wallet permissions correct (999:999)
All permissions set correctly for node2.

[... for all nodes ...]

Permission check completed for all nodes.

Press any key to continue...
```

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
Node: node2
Path: /opt/node2/config/validatorKey.pem

BLS Public Key:
b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Keys found: 2

Tip: You can copy a key by selecting it with your mouse.

Press any key to continue...
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
```

---

## 📊 Function Overview

| Function | Description |
|----|----|
| **Create Nodes** | Creates new validator nodes with automatic setup, key generation, and smart port assignment |
| **Update Nodes** | Updates configuration and Docker image while preserving all blockchain data and settings |
| **Start Nodes** | Starts one or all stopped nodes |
| **Stop Nodes** | Safely stops one or all running nodes |
| **Restart Nodes** | Restarts one or all nodes (useful after config changes) |
| **View Logs** | Real-time log viewer for debugging and monitoring |
| **Status Overview** | Shows all nodes with current status, ports, and uptime |
| **Fix Permissions** | Repairs directory permissions (999:999) for all node folders |
| **Extract BLS Keys** | Displays BLS Public Keys for each node (needed for validator registration) |

---

For questions or issues, please post in this thread.

---

## 🔄 Update: 12/20/2024

### 🔑 BLS Key Extraction

Added new feature to easily extract BLS Public Keys from your nodes.

* New menu option `[7] Extract BLS Public Keys` in Node Management
* Displays the BLS Public Key for each node (needed for validator registration)
* Shows status for missing or invalid key files
