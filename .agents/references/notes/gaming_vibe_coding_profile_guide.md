# Gaming & Vibe-Coding Profile Guide (GLM-5.3 744B)

This guide documents the configuration, resource budgeting, and execution steps for running **GLM-5.3 744B** locally while simultaneously playing modern AAA games on the host workstation.

---

## 1. Resource Allocation & Isolation Strategy

When playing games while running a 744B MoE model in the background, the primary risks are **VRAM contention (leading to game crashes / DirectX device lost)**, **CPU thread starvation (causing game micro-stutters and frame drops)**, and **system RAM exhaustion**.

The gaming profile establishes guaranteed hardware safety margins across all subsystems:

| Resource | Total Host Capacity | Colibrì Gaming Profile Allocation | Reserved for Gaming & OS | Protection Mechanism |
|---|---|---|---|---|
| **GPU 0: RTX PRO 6000 VRAM** | 97.8 GB (~96 GiB) | **70.3 GiB allocated** (dense trunk + 3,344 resident experts) | **27.5 GiB Free** (Abundant headroom for 4K ray-traced games & display) | `COLI_VK_TIER_GB=70.0`, `COLI_VK_TIER_RESERVE_GB=2.0` |
| **GPU 1: RTX 5090 VRAM** | 32.6 GB | **22.6 GiB allocated** (1,100 resident experts via DMA staging) | **9.9 GiB Free**, BAR1 usage safely bounded to **10 MiB** | `COLI_VK_DEV2=auto`, `COLI_VK_EXPERTS2=1100`, `COLI_VK_STAGED=1` |
| **Combined Resident VRAM Pool** | 130.4 GB | **94.36 GiB (4,444 resident experts)** | **37.4 GiB Combined Free VRAM** | 44.5% of GLM-5.3 pinned directly in ultra-fast GDDR VRAM |
| **Host System RAM** | 98.1 GB (91.5 GiB usable) | **70.0 GB budget** (16 cache slots/layer + 1,019 hot experts pinned) | **~21.5 GB Free & Available** | `RAM_GB=70`, `[RAM_GB=70.0] cap raised 8->16` |
| **AMD Ryzen 9 9950X CPU** | 16 Cores / 32 Threads | 8 Threads | **8 Physical Cores / 16 Threads Dedicated to Game** | `OMP_NUM_THREADS=8` |
| **Process CPU Scheduling** | Normal priority | `nice -n 12` | Highest priority for game physics & render loops | Linux kernel process preemption |
| **Storage Engine (I/O)** | Dual Samsung 9100 PRO | `DIRECT=1`, `PIPE=1`, `PIPE_WORKERS=16` | Direct I/O streaming at **6.04 GB/s** bypassing ext4 page locks | `O_DIRECT` + 16 asynchronous worker threads |

---

## 2. Server Configuration & Production Launcher

The dedicated launcher script is located at [scripts/start_gaming_profile.sh](file:///workspaces/colibri/scripts/start_gaming_profile.sh):

```bash
#!/usr/bin/env bash
# ==============================================================================
# Colibrì GLM-5.3 Gaming & Vibe-Coding Profile Launcher
# ==============================================================================
# Hardware Protections:
# - Reserves 27+ GB of VRAM on GPU 0 (RTX PRO 6000) for 4K games, DirectX/Vulkan & display.
# - Reserves 9+ GB of VRAM on GPU 1 (RTX 5090) and uses staged uploads (COLI_VK_STAGED=1) to prevent BAR1 exhaustion.
# - Leaves ~21+ GB of host system RAM completely free for game processes (RAM_GB=70 on 91+ GB system).
# - Retains native FP32 KV cache (KV8=0) to ensure Vulkan GPU dense chain (glmc_forward) accelerates agent prefill.
# - Allocates ~105,000 MB combined VRAM cache across dual GPUs (COLI_VK_TIER_GB=70.0 + DEV2=1100 experts).
# - Limits CPU OpenMP thread consumption to 8 threads (leaving 8 cores / 16 threads for games).
# - Launches with low OS priority (nice -n 12) to ensure game render loops are never preempted.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[Gaming Profile] Stopping any running server..."
python3 c/coli stop 2>/dev/null || true

echo "[Gaming Profile] Locking GPU clocks & setting persistence mode..."
nvidia-smi -pm 1 >/dev/null 2>&1 || true
nvidia-smi -lmc 14001,14001 >/dev/null 2>&1 || true
nvidia-smi -lgc 2100,2850 >/dev/null 2>&1 || true

echo "[Gaming Profile] Launching tuned Colibrì background server..."
nice -n 12 env \
  COLI_VULKAN=1 \
  COLI_MODEL=/models/glm-5.3 \
  COLI_VRAM_CACHE_MB=105000 \
  CTX=65536 \
  KV8=0 \
  RAM_GB=70 \
  DIRECT=1 \
  PIPE=1 \
  PIPE_WORKERS=16 \
  COLI_VK_STAGED=1 \
  COLI_VK_TIER_GB=70.0 \
  COLI_VK_TIER_RESERVE_GB=2.0 \
  COLI_VK_TIER_STREAM_SLOTS=16 \
  COLI_VK_TIER_STREAM_HALF=64 \
  COLI_VK_TIER_STREAM_ROWS=8 \
  COLI_VK_CHAIN_ROWS=128 \
  OMP_NUM_THREADS=8 \
  COLI_KV_SHARE=1 \
  COLI_VK_DEV2=auto \
  COLI_VK_EXPERTS2=1100 \
  COLI_VK_RESERVE2_GB=6.0 \
  python3 c/coli start --background --no-browser

echo "[Gaming Profile] Server started in background."
echo "[Gaming Profile] Run 'vibe-gaming chat' or 'vibe-gaming' to start vibe coding!"
```

---

## 3. Critical Architecture Guide: Why `KV8=0` is Strictly Required for Hermes Agent

> [!WARNING]
> **DO NOT SET `KV8=1` FOR HERMES AGENT WORKLOADS.**  
> Setting `KV8=1` causes Hermes agent prompts to take **47 minutes per turn** instead of **~20 seconds**. Always keep `KV8=0` in the gaming profile.

### 3.1 Empirical Test Comparison

During empirical verification of `vibe-gaming -z "What is 2+2?"`:
* **With `KV8=1`:** Turn 1 execution took **47 minutes, 17 seconds (`real 47m17.939s`)**.
* **With `KV8=0`:** Turn 1 execution took **~20–30 seconds**.

### 3.2 The Code Trap in [`c/glm_chain.h`](file:///workspaces/colibri/c/glm_chain.h#L720-L723)

Colibrì splits execution into two paths:
1. **The MoE Expert Tier:** Executes routed Mixture-of-Experts MLPs on the dual GPUs.
2. **The Dense Chain (`glmc_forward`):** Executes QKV projections, MLA attention matrices, RoPE embeddings, and RMSNorm across all 78 layers.

Line 722 of `c/glm_chain.h` defines the condition under which the GPU dense chain is allowed to execute:

```c
static int glmc_forward(Model *m, float *xh, int S, int pos_base) {
    if (!g_vk_chain) return 0;
    if (g_vk_chain == COLI_VK_CHAIN_PREFILL && S <= 2) return 0;
    if (g_pilot || g_pilot_real || g_looka || g_kv8 || g_tq ...) return 0; // <-- KV8 disables GPU dense chain
```

* **Vulkan Shaders are FP32-Only:** The engine's SPIR-V compute shaders for attention were compiled exclusively for FP32 KV cache tensors. There is no GPU compute shader for FP8 (`e4m3`) quantized attention.
* **The CPU Fallback:** When `KV8=1` is set, the engine outputs:
  ```text
  [VK] colibri: a quantized KV cache (KV8, KV_TQ) stays on the CPU: the dense chain stays off
  [VK] colibri: dense weights on the device and in host RAM (the dense part runs on the CPU)
  ```
  Every dense matrix multiply and attention calculation falls back to the **host CPU**.

### 3.3 Why `./coli chat` Felt Fast vs Why Hermes Agent Crawled

* **In casual CLI chat (`./coli chat`):** The prompt is only **5 to 20 tokens** ("Hi", "What is 2+2?"). Computing 10 tokens on the CPU is instantaneous (<0.1s), creating the illusion that `KV8=1` is blazing fast.
* **In Hermes Agent (`vibe-gaming`):** Hermes operates with tool calling. On turn 1, Hermes injects:
  - Complete system prompt and agent persona instructions.
  - JSON schemas for all 5 tools (`read_file`, `write_file`, `edit_file`, `terminal`, `search_files`).
  - Environment metadata and workspace paths.
  This creates an initial prompt of **3,757 tokens**.

Computing attention for 3,757 tokens across 78 layers on the CPU with 8 threads at `nice -n 12` took:
$$\text{CPU Prefill Time} = 78 \text{ layers} \times 35.8\text{ s/layer} = \mathbf{2,790.63\text{ seconds}} \approx \mathbf{46.5\text{ minutes!}}$$

### 3.4 What Actually Delivered the Speedup

The dramatic performance leap observed during earlier testing was **not** produced by `KV8=1`. It was produced by two other parameters:

1. **`RAM_GB=70` (Host RAM Expert Cache Expansion):**
   * Doubled the expert cache cap from 8 to **16 slots per layer** (`[RAM_GB=70.0] cap raised 8->16`).
   * Pinned **1,019 hot experts (21.6 GB)** permanently in system RAM, eliminating cold NVMe disk reads.
2. **`COLI_VRAM_CACHE_MB=105000` (Dual-GPU VRAM Resident Pool):**
   * Placed **4,444 experts (94.36 GiB)** in VRAM across both GPUs (3,344 on RTX PRO 6000 + 1,100 on RTX 5090).
   * Resulted in an extraordinary **99.8% GPU hit rate** (`device 2253011 of 2256600 routed experts (99.8%)`).

**Both of these massive optimizations work 100% with `KV8=0`.**

### 3.5 Summary Rule for Operators

| Mode | `KV8` Setting | GPU Dense Chain | Hermes 3,757 Token Prefill | Best Used For |
|---|---|---|---|---|
| **Agent / Hermes Mode** | **`KV8=0`** | **ENABLED (Vulkan GPU 0)** | **~15–25 seconds** | **Autonomous coding, multi-tool workflows, Hermes** |
| **Casual CLI Chat** | `KV8=1` | DISABLED (Host CPU) | 46.5 minutes (unusable for agents) | Short queries (<20 tokens) where minimizing KV RAM is paramount |

---

## 4. Dedicated Hermes Profile: `vibe-gaming`

A dedicated Hermes profile is configured at `/root/.hermes/profiles/vibe-gaming` with its wrapper script at `/root/.local/bin/vibe-gaming`.

### Profile Optimizations Applied:
1. **Zero Skill Bloat:**
   - Pruned all 58 bundled consumer/media skills via `hermes -p vibe-gaming skills opt-out --remove --yes`.
   - Only workspace-local engineering skills load when relevant.
2. **Clamped Reasoning:**
   - Configured `agent.reasoning_effort: low` to eliminate 20+ minute thinking pauses during tool calls.
3. **Live Streaming:**
   - Configured `streaming.enabled: true` and `display.streaming: true` so tokens stream in real time.
4. **Vibe-Coding `SOUL.md` Directive:**
   - Configured `/root/.hermes/profiles/vibe-gaming/SOUL.md` to mandate instant tool execution, extreme brevity, and clean shell output without conversational preamble.
5. **Context Protection:**
   - `compression.threshold: 0.35`, `compression.proactive_prune_tokens: 1024`, `protect_last_n: 6`.

---

## 5. How to Use the Gaming & Vibe-Coding Profile

### Step 1: Start the Server in Gaming Mode
```bash
/workspaces/colibri/scripts/start_gaming_profile.sh
```

### Step 2: Verify Memory Isolation & Clocks
```bash
# Check VRAM allocations (GPU 0 has ~27.5 GB free, GPU 1 has ~9.9 GB free)
nvidia-smi

# Check server health and resident expert count (should report 4,444 VRAM experts)
curl -s http://127.0.0.1:8000/health | jq .tiers
```

### Step 3: Launch Vibe-Coding with Hermes
Run the profile alias directly:
```bash
vibe-gaming
```
Or start an interactive chat session:
```bash
vibe-gaming chat
```
Or run a fast one-shot query:
```bash
vibe-gaming -z "Create a fast python benchmark for socket ping latency"
```

---

## 6. Host Mount Disk Space Tracking

When operating from the **host machine terminal** (outside the devcontainer where `/models` is mapped):
```bash
# Check the host mount target directly
du -sh /mnt/models_fast/models/* 2>/dev/null || du -sh /mnt/models_fast/*
df -h /mnt/models_fast
```
*Note: `/models` in the container maps to `/mnt/models_fast` on the host machine.*
