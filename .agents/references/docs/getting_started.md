# Colibrì & Hermes Agent Getting Started Guide

This guide provides instructions for linking binaries, starting and stopping the Colibrì inference engine, launching interactive chat sessions, and using Hermes Agent via both the Terminal User Interface (TUI) and headless one-shot commands.

---

## 1. Quick Architecture Overview

* **Colibrì Engine (`c/coli`, `c/colibri`):** Pure-C inference engine with Vulkan 1.4 GPU tiering and AVX-512 CPU acceleration.
* **Dual-GPU Tiering:** Primary GPU (NVIDIA RTX PRO 6000 Blackwell) holds dense weights and active experts; secondary GPU (NVIDIA RTX 5090 via `COLI_VK_DEV2`) holds additional expert sets.
* **NVMe Direct Streaming:** Cold experts stream dynamically from Samsung 9100 PRO NVMe (`/models/glm-5.3`) during forward passes.
* **OpenAI-Compatible Gateway:** Runs on `http://127.0.0.1:8000/v1` for external API and agent connections.
* **Hermes Agent (`vibe-gaming`):** Preconfigured local agent profile connected directly to Colibrì's API gateway.

---

## 2. Devcontainer Setup & Binary Linking

Inside the Devcontainer workspace:

### 1. Link Binary to Root Workspace
```bash
cd /workspaces/colibri
ln -sf /workspaces/colibri/c/coli ./coli
chmod +x ./coli /workspaces/colibri/c/coli
```

### 2. Verify Binary & Environment
Check the CLI help and engine status:
```bash
./coli --help
./coli status
```

### 3. Verify Downloaded Weights Directory
Ensure model weights are present on the dedicated NVMe drive:
```bash
ls -ld /models/glm*
```

*(Optional) Run health check verification:*
```bash
python3 ./coli doctor --model /models/glm-5.3
```

---

## 3. Running Colibrì Chat (Interactive CLI)

You can run interactive chat sessions directly in your terminal using either standalone engine mode or by attaching to an existing server.

### Option A: Direct Standalone Engine Chat
Spawns a dedicated private engine instance in your terminal:

```bash
cd /workspaces/colibri

COLI_VULKAN=1 \
COLI_VRAM_CACHE_MB=105000 \
CTX=65536 \
KV8=1 \
COLI_MODEL=/models/glm-5.3 \
./coli chat \
  --model glm-5.3 \
  --ram 70
```

#### Environment Variables Explained:
* `COLI_VULKAN=1`: Enables Vulkan GPU compute acceleration.
* `COLI_VRAM_CACHE_MB=105000`: Sets VRAM allocation cap across GPUs.
* `CTX=65536`: Configures the context window size (up to 64k tokens).
* `KV8=1`: Quantizes KV-cache to 8-bit to save memory and boost throughput.
* `COLI_MODEL=/models/glm-5.3`: Path to model shard weights.
* `--ram 70`: Reserves up to 70 GB host RAM for expert staging and caching.

---

### Option B: Attached Chat (Recommended for Instant Startup)
If a background server (`coli serve` or `coli web`) is already running, attach directly without reloading model weights:

```bash
cd /workspaces/colibri
./coli chat --attach
```
> **Tip:** `--attach` connects to `http://127.0.0.1:8000` immediately, keeping the expert cache warm across sessions.

---

## 4. Starting the Background Service & Web Dashboard

To run Colibrì as an OpenAI-compatible background API server or Web UI:

### Start OpenAI API Server
```bash
cd /workspaces/colibri

COLI_VULKAN=1 \
COLI_VRAM_CACHE_MB=105000 \
CTX=65536 \
KV8=1 \
COLI_MODEL=/models/glm-5.3 \
./coli serve \
  --model /models/glm-5.3 \
  --ram 70 \
  --host 0.0.0.0 \
  --port 8000
```

### Start Web UI Dashboard Mode
```bash
cd /workspaces/colibri
./coli web --model /models/glm-5.3 --host 0.0.0.0 --port 8000 --no-browser
```

### Check Server Status & Recent Logs
```bash
# Check if server is running, PID, and endpoints:
./coli status

# View recent engine and server log output:
./coli logs
```

---

## 5. Stopping Colibrì Services

### Graceful Shutdown via CLI
Stop the active server and shut down the backend C engine cleanly:
```bash
cd /workspaces/colibri
./coli stop
```

If running on a custom port:
```bash
./coli stop --port 8000
```

### Verify Shutdown
```bash
./coli status
```

*(Emergency fallback if process is unresponsive):*
```bash
pkill -f "/workspaces/colibri/c/colibri"
pkill -f "coli (serve|web|chat)"
```

---

## 6. Using Hermes Agent (`vibe-gaming`)

The `vibe-gaming` CLI wrapper (`/root/.local/bin/vibe-gaming`) invokes Hermes Agent preconfigured to target the local Colibrì engine (`http://127.0.0.1:8000/v1`) using model `glm-5.2-colibri`.

> **Prerequisite:** Ensure Colibrì server is running before launching Hermes (`./coli status` must report `server ready`).

### 1. Interactive Terminal User Interface (TUI)
Launch the modern curses-based interactive agent dashboard:
```bash
vibe-gaming chat --tui
# Or shorthand:
vibe-gaming --tui
```
* Use arrow keys and mouse to navigate sessions, tool results, and responses.
* Type `/help` inside the TUI for keybindings and options.

### 2. Interactive CLI Chat (Classic REPL)
```bash
vibe-gaming chat
```

### 3. One-Shot / Headless Commands (`-z`)
Execute single prompts autonomously without entering an interactive loop:
```bash
# Basic query
vibe-gaming -z "What is 2+2?"

# Repository search and code inspection
vibe-gaming -z "Search for 'vkt_stream_prefetch' in c/ and report its signature."
```

### 4. Session Management
```bash
# List past sessions:
vibe-gaming sessions list

# Resume the most recent session:
vibe-gaming chat --resume latest

# Resume a specific session by ID:
vibe-gaming chat --resume <session_id>
```

---

## 7. Command Cheat Sheet

| Task | Command |
| :--- | :--- |
| **Check Status** | `./coli status` |
| **Check Logs** | `./coli logs` |
| **Start Server** | `COLI_VULKAN=1 ./coli serve --model /models/glm-5.3 --ram 70 --host 0.0.0.0 --port 8000` |
| **Stop Server** | `./coli stop` |
| **Interactive Engine Chat** | `COLI_VULKAN=1 ./coli chat --model glm-5.3 --ram 70` |
| **Attach to Running Engine** | `./coli chat --attach` |
| **Launch Hermes TUI** | `vibe-gaming --tui` |
| **Launch Hermes CLI Chat** | `vibe-gaming chat` |
| **Hermes One-Shot Query** | `vibe-gaming -z "<prompt>"` |
| **List Hermes Sessions** | `vibe-gaming sessions list` |
| **Resume Latest Session** | `vibe-gaming chat --resume latest` |
