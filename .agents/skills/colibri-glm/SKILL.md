---
name: colibri-glm
description: >-
  Procedures, runbooks, and command sequences for compiling, downloading,
  configuring, switching, and serving GLM-5.3 and GLM-5.3-Flash models locally on the
  Colibrì C engine with Vulkan GPU tiering, hardware headroom verification, and dual-NVMe disk storage.
---

# Colibrì GLM Execution Skill & Hardware Runbook

This skill provides mandatory operational procedures, hardware verification protocols, and runbooks for managing and serving **GLM-5.3 (744B Flagship)** and **GLM-5.3-Flash (321B Multimodal)** on the local workstation using the Colibrì pure-C engine.

---

## 1. Mandatory Pre-Execution Verification Protocol ("Check Before You Touch")

> [!IMPORTANT]
> **RULE: NEVER LAUNCH OR SWITCH MODELS WITHOUT RUNNING THE PRE-FLIGHT CHECK FIRST.**
> The agent must verify existing process states, GPU VRAM allocations, and host RAM headroom *before* executing any model load or server startup. Launching without checking causes VRAM over-allocation or triggers the Linux kernel OOM killer (`systemd-oomd`).

### Step 1.1: Check Active Processes & Server Status
```bash
python3 /workspaces/colibri/c/coli status
ps aux | grep -E "colibri|glm53"
```
* If a server is reported as `ready` or `loading`, identify which model is running before proceeding.

### Step 1.2: Check GPU VRAM Allocations & Clocks
```bash
nvidia-smi
```
* **Verify Free VRAM:**
  * If switching models: existing engine processes **must be stopped** until GPU 0 reports $\le 2$ GB used and GPU 1 reports $\le 200$ MB used.
  * If a model is active: ensure GPU 0 has $\ge 24$ GB unallocated VRAM free for display and gaming/simulation headroom.

### Step 1.3: Check Host System RAM Headroom
```bash
free -h
```
* **Verify Available RAM:**
  * Host RAM total: **91 GiB**.
  * Available RAM must stay $\ge 45$ GiB at all times to prevent the host kernel OOM killer from terminating background processes.

### Step 1.4: Check NVMe Storage Headroom
```bash
df -h /models /workspaces/colibri
```
* `/models` (`/dev/nvme1`): Primary model store.
* `/workspaces/colibri` (`/dev/nvme0`): Fast Gen 5 x4 store and dual-NVMe model mirror.

---

## 2. Model Switching & Clean Teardown Procedure

To switch between GLM-5.3 (744B) and GLM-5.3-Flash (321B), you **must** execute a clean teardown to completely free GPU VRAM and host RAM buffers:

```bash
# 1. Issue graceful stop command
python3 /workspaces/colibri/c/coli stop

# 2. Verify engine processes have exited
ps aux | grep -E "colibri|glm53"

# 3. Verify VRAM has returned to idle baseline (GPU 0 ~1.5 GB, GPU 1 ~110 MB)
nvidia-smi

# 4. (Emergency Fallback Only - if process hangs):
# pkill -9 -f "/workspaces/colibri/c/colibri"
# pkill -9 -f "/workspaces/colibri/c/glm53"
```

---

## 3. Hardware Coexistence Invariants (Gaming & IsaacLab-Arena / VLA Headroom)

The workstation operates under strict multi-tenant hardware constraints. Local LLM serving must run concurrently with heavy workloads:
1. **Workstation 4K Ray-Traced Gaming:** DirectX 12 / Unreal Engine 5 render loops driving 4K high-refresh displays.
2. **IsaacLab-Arena Robot Simulation & Vision-Language-Action (VLA) Inference:**
   - Real-time PhysX rigid-body simulation and Omniverse RTX sensor rendering.
   - VLA policy models (e.g. OpenVLA, Octo, Cosmos) running concurrently on CUDA.
   - 20–25 GB host RAM for USD stages, robot meshes, and physics buffers.

### Hardware Protection Budget:
* **GPU 0 (RTX PRO 6000 96GB):** Colibrì allocations capped at $\le 70$ GiB, guaranteeing **$\ge 25–28$ GiB FREE VRAM** for IsaacLab rendering / 4K gaming.
* **GPU 1 (RTX 5090 32GB):** Allocations capped at $\le 23$ GiB with `COLI_VK_STAGED=1` (DMA staging queue uploads, 10 MB BAR1 usage), guaranteeing **$\ge 9–10$ GiB FREE VRAM**.
* **Host System RAM (91GB):** Total Colibrì process RSS capped at $\le 36$ GiB, guaranteeing **$\ge 50$ GiB FREE RAM** (zero risk of kernel OOM kills).
* **CPU Scheduling:** `OMP_NUM_THREADS=8` pinned at `nice -n 12`, leaving 8 dedicated physical cores (16 threads) 100% idle for physics simulation loops.

---

## 4. Engine Compilation

Compile both engines with native AVX-512 vectorization and Vulkan acceleration:

```bash
# 1. Compile GLM-5.3 Flagship engine (c/colibri)
make -C /workspaces/colibri/c colibri VK=1 ARCH=native

# 2. Compile GLM-5.3-Flash engine (c/glm53)
make -C /workspaces/colibri/c glm53 VK=1 ARCH=native
```

---

## 5. Model Profiles & Launcher Runbooks

### 5.1 Profile A: GLM-5.3 (744B Flagship MoE)
* **Storage Path:** `/models/glm-5.3` (141 shards, 419.3 GB)
* **Dual-NVMe Mirror:** `/workspaces/colibri/models_mirror/glm-5.3` (141 shards, 16.16 GB/s)
* **Launcher Script:** [`scripts/start_gaming_profile.sh`](file:///workspaces/colibri/scripts/start_gaming_profile.sh)
* **Launch Command:**
  ```bash
  /workspaces/colibri/scripts/start_gaming_profile.sh
  ```
* **Hermes Agent Command:**
  ```bash
  vibe-gaming chat        # Interactive TUI / REPL
  vibe-gaming -z "<prompt>" # Headless one-shot
  ```

### 5.2 Profile B: GLM-5.3-Flash (321B Multimodal MoE)
* **Storage Path:** `/models/glm-5.3-flash` (62 shards, 182.0 GB)
* **Engine Binary:** [`c/glm53`](file:///workspaces/colibri/c/glm53)
* **CRITICAL OOM PREVENTION KNOB:** You **must** set `GLM53_EXPERT_GB=18.0`. Without this setting, `c/glm53.c` attempts to allocate `free_now - 3.0` (79.5 GB RAM) and is immediately killed by the Linux kernel OOM killer (`systemd-oomd`).
* **Launcher Script:** [`scripts/start_flash_profile.sh`](file:///workspaces/colibri/scripts/start_flash_profile.sh)
* **Launch Command:**
  ```bash
  /workspaces/colibri/scripts/start_flash_profile.sh
  ```
* **Hermes Agent Command:**
  ```bash
  vibe-flash chat         # Interactive TUI / REPL
  vibe-flash -z "<prompt>"  # Headless one-shot
  ```

---

## 6. Verification & Health Check Commands

| Target | Command | Expected Output |
| :--- | :--- | :--- |
| **Server Status** | `python3 c/coli status` | `server ready (pid ...)`, `openai http://127.0.0.1:8000/v1` |
| **API Health Check** | `curl -s http://127.0.0.1:8000/v1/models \| jq` | JSON response with model ID (`glm-5.3-flash-colibri` or `glm-5.2-colibri`) |
| **Live VRAM Audit** | `nvidia-smi` | GPU 0: $\ge 25$ GB free; GPU 1: $\ge 10$ GB free |
| **Host RAM Audit** | `free -h` | Available RAM: $\ge 50$ GiB |
| **Model Shards Check** | `python3 c/coli doctor --model /models/<model>` | Safetensors headers valid, family registered |
| **Test Query** | `curl -s http://127.0.0.1:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"glm-5.3-flash-colibri","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":16}'` | Immediate response `"4"` |

---

## 7. Troubleshooting & Recovery Runbook

1. **Server Exits with Signal 9 (SIGKILL / OOM):**
   - Check kernel logs: `dmesg -T | grep -i -E "killed|oom"`
   - If killed by OOM killer: ensure `GLM53_EXPERT_GB=18.0` and `RAM_GB=35.0` are set in the environment. Never run `glm53` without capping `GLM53_EXPERT_GB`.
2. **GPU Downclocking to P8 Idle (405 MHz):**
   - Lock GDDR clocks: `nvidia-smi -pm 1 && nvidia-smi -lmc 14001,14001 && nvidia-smi -lgc 2100,2850`.
3. **Display TDR Reset / Timeout:**
   - Ensure `COLI_VK_CHAIN_ROWS=128` is set to bound Vulkan attention passes to small chunks.
4. **BAR1 Address Space Exhaustion on GPU 1 (`0x00000051`):**
   - Ensure `COLI_VK_STAGED=1` is active so weights upload via DMA transfer queues instead of mapping through the host-visible aperture.
