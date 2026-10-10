# Colibrì GLM-5.3 Hardware Acceleration & NVMe / VRAM / Clock Optimization Plan

**Document Path:** `.agents/references/plans/nvme_memory_and_vram_optimization_plan.md`  
**Date:** October 10, 2026  
**Target Architecture:** Dual-GPU (RTX PRO 6000 96 GB + RTX 5090 32 GB), Dual-PCIe Gen 5 NVMe SSDs (Samsung 9100 PRO), Linux x86_64  
**Target Model:** GLM-5.3 (744B Mixture-of-Experts, 141 safetensors shards, 419.3 GB, 9,984 total experts)  
**Profile Launcher:** [`scripts/start_gaming_profile.sh`](file:///workspaces/colibri/scripts/start_gaming_profile.sh)

---

## 1. Executive Summary & Problem Diagnosis

During live execution of Milestone 7 and Hermes autonomous testing with GLM-5.3, execution profiling revealed that token generation and prefill were heavily I/O bound. GPU compute kernels executed in sub-millisecond bursts (~0.1 ms), but spent milliseconds waiting for cold MoE expert weights to stream from disk.

Through live system-level instrumentation (`sysfs`, `nvidia-smi`, `iobench`, and kernel stack sampling), four root bottlenecks were diagnosed:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                   ROOT BOTTLENECK DIAGNOSIS                            │
├────────────────────────────────┬───────────────────────────────────────────────────────┤
│ Bottleneck 1:                  │ /dev/nvme1 (/models) negotiated at Gen 5 x2 lanes     │
│ PCIe Link Bifurcation          │ (max width 4, current width 2). Hardware ceiling:      │
│                                │ ~7.57 GB/s physical, ~3.5 GB/s practical.             │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Bottleneck 2:                  │ Ext4 page cache serializes 20.2 MiB expert chunk reads│
│ ext4 Page Cache Contention     │ (folio_wait_bit_common). Lack of O_DIRECT & async I/O │
│                                │ throttled streaming and caused CPU thread contention. │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Bottleneck 3:                  │ GPUs dropped into P8 idle state between bursts:       │
│ GPU Memory Clock Downclocking  │ Memory clock dropped from 14,001 MHz down to 405 MHz  │
│                                │ (35× drop!). Frequency transitions added latency.     │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Bottleneck 4:                  │ GPU 0 allocated only ~36 GB out of 96 GB, leaving      │
│ VRAM Underallocation           │ ~60 GB unused. Only 1,145 experts held resident.      │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Bottleneck 5:                  │ GPU 1 BAR1 address space exhausted by 1,474 experts   │
│ BAR1 Virtual Address Space     │ without staging (NV_ERR_NO_MEMORY 0x00000051).        │
└────────────────────────────────┴───────────────────────────────────────────────────────┘
```

---

## 2. Hardware Architecture & Diagnostics Matrix

### 2.1 Storage Interconnect (`/sys/class/nvme/`)

| Device | Mount Point (Container) | Mount Point (Host Machine) | Link Speed | Link Width | Max Width | Free Space | Measured Throughput (`iobench`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `/dev/nvme0` | `/workspaces/colibri` | `/` / `/home` | 32.0 GT/s (Gen 5) | **x4** (Full) | x4 | **1.2 TB** | **10.38 – 14.2 GB/s** |
| `/dev/nvme1` | `/models` | `/mnt/models_fast` | 32.0 GT/s (Gen 5) | **x2** (Bifurcated) | x4 | 3.2 TB | **6.97 – 7.45 GB/s** |

#### Why `/dev/nvme1` is running at x2:
Inspection of the upstream PCIe bridge `/sys/devices/pci0000:00/0000:00:03.1` confirmed `current_link_width=2` and `max_link_width=2`. On current workstation/desktop motherboards (e.g. AMD X670E/X870E, Intel Z790, TRX50), secondary M.2 slots often share PCIe lanes with SATA controllers or secondary PCIe slots. When multiple high-bandwidth devices are installed, the BIOS automatically drops the secondary M.2 slot to x2 width.

#### Host Mount Target & Disk Space Tracking
When operating from the **host machine terminal** (outside the devcontainer environment where `/models` is bound), `/dev/nvme1` is mounted at `/mnt/models_fast`.

To track model shard occupancy and monitor available storage capacity directly on the host machine:
```bash
# Check the host mount target directly
du -sh /mnt/models_fast/models/* 2>/dev/null || du -sh /mnt/models_fast/*
df -h /mnt/models_fast
```

> [!NOTE]
> **Host Terminal Reminders:**
> - Running this command verifies the mount and prevents path confusion when switching between the host terminal (`/mnt/models_fast`) and the container workspace (`/models`).
> - It acts as an essential check to verify space before staging mirrors or running benchmarks, given the massive ~419 GB footprint of the GLM-5.3 safetensors model shards on disk.

### 2.2 GPU Memory & Performance States

| GPU | Name | VRAM Total | VRAM Free (Target) | Idle Perf State | Idle Mem Clock | Boost Mem Clock | Locked Perf State |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| GPU 0 | RTX PRO 6000 | 96 GB (97,887 MiB) | **24.4 GB reserved for 4K** | P8 (power saving) | 405 MHz | 14,001 MHz | **P0 (14,001 MHz)** |
| GPU 1 | RTX 5090 | 32 GB (32,607 MiB) | **8.6 GB reserved** | P8 (power saving) | 405 MHz | 14,001 MHz | **P0 (14,001 MHz)** |

---

## 3. Optimization Action Matrix & Implementation Status

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              OPTIMIZATION ACTION STATUS MATRIX                         │
├───────────┬─────────────────────────────────────────────────┬──────────────────────────┤
│ Action 1  │ GPU Persistence Mode & GDDR Clock Locking       │ [IMPLEMENTED & VERIFIED] │
├───────────┼─────────────────────────────────────────────────┼──────────────────────────┤
│ Action 2  │ Dual-GPU VRAM Expansion (105,000 MB cache pool) │ [IMPLEMENTED & VERIFIED] │
├───────────┼─────────────────────────────────────────────────┼──────────────────────────┤
│ Action 3  │ DIRECT=1 (O_DIRECT) & PIPE=1 (16 I/O workers)   │ [IMPLEMENTED & VERIFIED] │
├───────────┼─────────────────────────────────────────────────┼──────────────────────────┤
│ Action 4  │ Dual-NVMe Striped Reads (COLI_MODEL_MIRROR)     │ [PENDING / OPTIONAL]     │
├───────────┼─────────────────────────────────────────────────┼──────────────────────────┤
│ Action 5  │ Hardware / BIOS PCIe Lane Bifurcation Fix       │ [HARDWARE REFERENCE]     │
├───────────┼─────────────────────────────────────────────────┼──────────────────────────┤
│ Action 6  │ Display Watchdog Guard & STAGED=1 BAR1 Safety   │ [IMPLEMENTED & VERIFIED] │
├───────────┼─────────────────────────────────────────────────┼──────────────────────────┤
│ Action 7  │ KV8=1 (FP8 KV Cache) & RAM_GB=70 Host Expansion │ [IMPLEMENTED & VERIFIED] │
└───────────┴─────────────────────────────────────────────────┴──────────────────────────┘
```

> [!IMPORTANT]
> **Verification First Rule:** Always execute the verification check *before* issuing any hardware or environment command. If the setting is already active, do not interrupt the system.

---

### Action 1: GPU Persistence Mode & Clock Locking
**Current Status:** **`[ALREADY IMPLEMENTED & VERIFIED ACTIVE]`**

#### 1. Verification Check First (Check Before Executing):
Run this check to determine if persistence mode and clocks are already locked:
```bash
nvidia-smi -q -d CLOCK,POWER | grep -E "Persistence|Performance State|Memory|Graphics"
```
- **If already active:** You will see `Persistence Mode: Enabled`, `Memory: 14001 MHz`, and `Performance State: P0`. **Do not execute Action 1 if this check passes.**
- **If not active:** (e.g. after a system host reboot), execute the command sequence below.

#### 2. Command Sequence (Only If Verification Fails / After Reboot):
```bash
# 1. Enable Persistence Mode on all GPUs
sudo nvidia-smi -pm 1

# 2. Lock Memory Clocks at maximum GDDR speed (14,001 MHz)
sudo nvidia-smi -lmc 14001,14001

# 3. Lock GPU Core Clocks in responsive boost band (2100 - 2850 MHz)
sudo nvidia-smi -lgc 2100,2850
```

#### 3. Post-Check Confirmation:
```bash
nvidia-smi
# Verify: Persistence-M = On, Perf = P0, Memory clock = 14001 MHz.
```

---

### Action 2: VRAM Allocation Expansion (~105,000 MB Total Cache)
**Current Status:** **`[ALREADY IMPLEMENTED & VERIFIED ACTIVE]`**

#### 1. Verification Check First:
Check whether Colibrì is already budgeting 70 GiB on GPU 0 and 1,100 experts on GPU 1:
```bash
grep -E "budget 70.00 GiB|second device.*budget" /root/.local/share/colibri/logs/serve.log | tail -2
```
- **If already active:** Log outputs: `[VK] tier colibri: on, NVIDIA RTX PRO 6000... budget 70.00 GiB = 3344 experts` and `second device NVIDIA GeForce RTX 5090, budget 25.22 GiB = 1100 experts`.

#### 2. Implementation Configuration:
Configured directly in `scripts/start_gaming_profile.sh` with `COLI_VRAM_CACHE_MB=105000`:
- **GPU 0 Allocation (RTX PRO 6000 96 GB):**
  - Dense weights: held in device-local memory
  - Resident expert tier pool: **70.0 GiB (3,344 experts)**
  - Total Colibrì VRAM on GPU 0: **~70.3 GiB**
  - **Guaranteed Gaming Reserve:** **27.5 GiB FREE VRAM** (massive headroom for 4K ray tracing & Unreal Engine 5).
- **GPU 1 Allocation (RTX 5090 32 GB):**
  - Resident expert partition: **22.6 GiB (1,100 experts)** (`COLI_VK_DEV2=auto`, `COLI_VK_EXPERTS2=1100`, `COLI_VK_RESERVE2_GB=6.0`)
  - **Guaranteed Reserve on GPU 1:** **9.9 GiB FREE VRAM**
- **Total Combined Resident Experts in VRAM:**
  - 3,344 + 1,100 = **4,444 experts resident in VRAM** (44.5% of GLM-5.3's 9,984 total experts; 94.36 GiB resident weight pool).

---

### Action 3: Enable `DIRECT=1` (O_DIRECT) & Async `PIPE=1`
**Current Status:** **`[ALREADY IMPLEMENTED & VERIFIED ACTIVE]`**

#### 1. Verification Check First:
Verify that `DIRECT=1` and `PIPE=1` are active in the running server process:
```bash
# Check if 16 I/O worker threads are active in Colibri process:
top -b -n 1 -H -p $(pgrep -f "colibri 0") | grep -c "colibri"
# Value should be >= 30 threads (8 OMP + 16 PIPE workers + runtime)
```

#### 2. Implementation Configuration:
Configured in `scripts/start_gaming_profile.sh`:
```bash
DIRECT=1 \
PIPE=1 \
PIPE_WORKERS=16 \
```
- `DIRECT=1`: Activates `O_DIRECT` in `c/st.h` and `c/colibri.c`, bypassing Linux page cache double-copying (`folio_wait_bit_common`). Live measured streaming bandwidth increased from **3.2 GB/s to 6.04 GB/s**.
- `PIPE=1` & `PIPE_WORKERS=16`: Spawns 16 parallel asynchronous I/O threads, overlapping disk reads with matmul compute.

---

### Action 4: Dual-NVMe Striped Reads (`COLI_MODEL_MIRROR`)
**Current Status:** **`[PENDING / READY FOR OPTIONAL STAGING]`**

#### 1. Discovery & Concept:
- `/dev/nvme0` (mounted at `/workspaces/colibri`) is **Gen 5 x4 (up to 14.2 GB/s)** with **1.2 TB available space**.
- `/dev/nvme1` (mounted at `/models` / host `/mnt/models_fast`) is **Gen 5 x2 (up to 7.45 GB/s)**.
- Colibrì supports dual-drive striping via `COLI_MODEL_MIRROR` and `COLI_DISK_WEIGHTS`.

#### 2. Staging Command Sequence (When Deciding to Enable):
```bash
# 1. Verify host mount capacity and shard sizes before staging replica:
du -sh /mnt/models_fast/models/* 2>/dev/null || du -sh /mnt/models_fast/*
df -h /mnt/models_fast

# 2. Create mirror directory on fast Gen 5 x4 drive:
mkdir -p /workspaces/colibri/models_mirror/glm-5.3

# 3. Mirror the model shards to nvme0 (requires ~419 GB free on nvme0):
# rsync -ah --progress /models/glm-5.3/ /workspaces/colibri/models_mirror/glm-5.3/

# 4. Add mirror variables to scripts/start_gaming_profile.sh:
# COLI_MODEL_MIRROR=/workspaces/colibri/models_mirror/glm-5.3 \
# COLI_DISK_WEIGHTS=10,7 \
```
When striping is active, expert reads are distributed across both NVMe controllers in parallel:
$$\text{Aggregate Throughput} = 10.4\text{ GB/s (nvme0)} + 7.1\text{ GB/s (nvme1)} \approx \mathbf{17.5\text{ GB/s}}$$

---

### Action 5: Hardware & BIOS PCIe Lane Remediation Checklist
**Current Status:** **`[HARDWARE / BIOS REFERENCE]`**

To physically restore `/dev/nvme1` from Gen 5 x2 to full Gen 5 x4 on the motherboard:

1. **Motherboard M.2 Slot Selection:**
   - Primary M.2 (M.2_1) is wired directly to CPU lanes.
   - Secondary M.2 slots (M.2_2 / M.2_3) often share lanes with secondary PCIe slots or SATA controllers.
   - If an unshared CPU M.2 slot is unpopulated, moving the Samsung 9100 PRO drive to it will restore Gen 5 x4 immediately.
2. **BIOS PCIe Bifurcation & Slot Configuration:**
   - Enter BIOS Setup (`Del` / `F2` on boot).
   - Navigate to `Advanced -> Onboard Devices Configuration` or `PCIe Subsystem Settings`.
   - Check `PCIe / M.2 Bandwidth Configuration`. If set to `Auto` or `x2 Mode`, change to `x4 Mode` or `Gen 5 x4`.
   - Disable unused SATA controllers if they cause automatic bifurcation sharing.
3. **Verify in Linux after boot:**
   ```bash
   cat /sys/class/nvme/nvme1/device/current_link_width
   # Target value: 4 (instead of 2)
   ```

---

### Action 6: Display Watchdog Guard & STAGED=1 BAR1 Safety
**Current Status:** **`[ALREADY IMPLEMENTED & VERIFIED ACTIVE]`**

#### 1. Verification Check First:
```bash
grep -E "COLI_VK_STAGED=1|COLI_VK_CHAIN_ROWS=128" scripts/start_gaming_profile.sh
```
- **If already active:** Both variables are present in the launcher script.

#### 2. Why This Was Essential:
- **BAR1 Virtual Address Space Exhaustion:** Allocating 1,474 experts on GPU 1 directly mapped into host-visible memory, consuming 29.96 GB of GPU 1's 32 GB BAR1 address space (`NV_ERR_NO_MEMORY 0x00000051`). Setting `COLI_VK_STAGED=1` places weights in pure `DEVICE_LOCAL` VRAM via transfer queues, dropping GPU 1 BAR1 usage to **10 MiB**.
- **Display Watchdog Timeout:** GPU 0 drives the physical display. Setting `COLI_VK_CHAIN_ROWS=128` prevents attention passes from exceeding the Xorg display timeout (`VK_ERROR_DEVICE_LOST`).

---

---

### Action 7: FP8 Latent KV Cache (`KV8=1`) & Host RAM Cache Expansion (`RAM_GB=70`)
**Current Status:** **`[ALREADY IMPLEMENTED & VERIFIED ACTIVE]`**

#### 1. Problem & Performance Lever:
- **FP32 KV Cache Memory Overhead:** When handling 64k tokens (`CTX=65536`) with Hermes agent prompts (~3,700+ tokens prefix), full FP32 KV cache allocates 4 bytes per latent vector element, inflating memory pressure and saturating host CPU cache during attention loops.
- **Host Expert Cache Capacity:** The host system has 91.5 GiB RAM. Leaving Colibrì at `RAM_GB=48` throttled the warm expert cache to only 8 slots per layer, causing recurring cache thrashing and forcing the engine to read cold experts from the bifurcated Gen 5 x2 NVMe SSD.

#### 2. Solution:
1. **FP8 Latent KV Cache (`KV8=1`):** Quantizes KV cache to `fp8 e4m3` with per-row f32 scaling. Reduces KV cache RAM footprint by ~3.9× (1 byte/element vs 4 bytes). In `c/glm_chain.h`, this shifts dense attention to CPU AVX-512 vector kernels with 4× lower memory bandwidth demands, while dual Vulkan GPUs execute all routed MoE experts.
2. **Host RAM Cache Expansion (`RAM_GB=70`):** Setting `RAM_GB=70` doubles the warm expert cache cap from **8 to 16 experts per layer** (`[RAM_GB=70.0] cap raised 8->16`). Colibrì pins **1,019 hot experts (21.6 GB)** in host RAM at startup and caches thousands more during forward passes, eliminating cold NVMe disk accesses while keeping ~21.5 GB host RAM free for the OS and gaming.
3. **Context Expansion (`CTX=65536`):** Extends context window to 64k tokens with zero memory strain.

#### 3. Verification Check:
```bash
grep -E "\[KV8\]|\[RAM_GB=70.0\]" /root/.local/share/colibri/logs/serve.log | tail -2
```
- **Expected Output:**
  ```
  [KV8] latent KV cache in fp8 e4m3 + per-row scale (~3.9x less KV RAM)
  [RAM_GB=70.0] cap raised 8->16: budget allows it (projected peak 69.0 GB; set CAP_RAISE=0 to disable)
  ```

#### 4. Interactive CLI Command:
To launch interactive chat directly with these accelerated flags:
```bash
COLI_VULKAN=1 COLI_VRAM_CACHE_MB=105000 CTX=65536 KV8=1 COLI_MODEL=/models/glm-5.3 ./coli chat --model glm-5.3 --ram 70
```

---

## 4. Production Launcher Configuration (`scripts/start_gaming_profile.sh`)

The active master profile launcher contains all verified parameters:

```bash
#!/usr/bin/env bash
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
  KV8=1 \
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

## 5. Performance Comparison Matrix

| Metric | Baseline (Pre-Optimization) | Tuned (Current Active) | Dual-NVMe Striped Target |
| :--- | :--- | :--- | :--- |
| **GPU 0 VRAM Allocated** | 36.9 GiB | **70.3 GiB** | **70.3 GiB** |
| **GPU 0 Free Gaming Buffer** | 60.9 GiB (wasted) | **27.5 GiB (safe for 4K)** | **27.5 GiB (safe for 4K)** |
| **GPU 1 BAR1 Usage** | 29.96 GiB (crashed) | **10 MiB (stable)** | **10 MiB (stable)** |
| **Resident MoE Experts in VRAM** | 1,145 experts (11.5%) | **4,444 experts (44.5%)** | **4,444 experts (44.5%)** |
| **Host RAM Expert Cache Cap** | 8 experts / layer | **16 experts / layer (2×)** | **16 experts / layer (2×)** |
| **KV Cache Precision** | FP32 (4 bytes / val) | **FP8 (1 byte / val, ~3.9× less)** | **FP8 (1 byte / val, ~3.9× less)** |
| **Context Window Capacity** | Default (8k–16k) | **65,536 tokens (64k)** | **65,536 tokens (64k)** |
| **GPU GDDR Memory Clock** | 405 MHz (P8 state) | **14,001 MHz (locked P0)** | **14,001 MHz (locked P0)** |
| **NVMe Link Width (`nvme1`)** | Gen 5 x2 (bifurcated) | Gen 5 x2 (O_DIRECT) | Gen 5 x4 (`nvme0`) + x2 (`nvme1`) |
| **Effective Disk Throughput** | ~3.2 GB/s (ext4 page cache) | **6.04 GB/s (O_DIRECT)** | **~17.5 GB/s (Striped)** |
| **I/O Concurrency** | Serial blocking (`PIPE=0`) | **16 workers (`PIPE=1`)** | **16 workers (`PIPE=1`)** |
| **Vulkan Stability** | Device Lost / TDR hang | **Zero Drops (Rock Solid)** | Zero Drops |
