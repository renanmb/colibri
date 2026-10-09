# Preparation Summary & Technical Reference: Running GLM-5.3 on Colibrì

This document consolidates all findings, architectural decisions, hardware configurations, and troubleshooting steps completed to prepare this system for running **GLM-5.3** locally using the **Colibrì** engine.

---

## 1. Project Background & Core Philosophy

### What is Colibrì?
- **Author:** Vincenzo Fornaro ([JustVugg/colibri](https://github.com/JustVugg/colibri)).
- **Tagline:** *"Tiny engine, immense model."*
- **Design Principles:**
  - Written in **pure C**, with zero heavy runtime dependencies (no PyTorch, no CUDA runtime bloat).
  - One dedicated C file per model architecture family ([`c/colibri.c`](file:///workspaces/colibri/c/colibri.c) for GLM-5.2/5.3, [`c/glm53.c`](file:///workspaces/colibri/c/glm53.c) for GLM-5.3-Flash).
  - OpenMP multithreading + native vector intrinsics (AVX2, AVX-512, NEON).
  - Cross-platform GPU acceleration via **Vulkan 1.2+** and CUDA.

### The Streaming MoE Paradigm ("The Disk is the Wall")
- A frontier Mixture-of-Experts (MoE) model like GLM-5.3 has **744 Billion total parameters**, but only activates ~40B parameters (~5.4%) per generated token.
- Between consecutive tokens, only **~11 GB of routed experts** are needed.
- **Placement Strategy:**
  1. **Dense weights stay resident in RAM/VRAM:** Embeddings, attention projections, shared experts, layer norms, and routers (~9.9 GB total for GLM-5.3).
  2. **Routed experts stream on-demand from NVMe SSD:** Experts are loaded dynamically based on router predictions into an adaptive LRU cache.
  3. **GPU Expert Tiering:** Frequently activated experts are cached directly in GPU VRAM ([`c/vk_tier.c`](file:///workspaces/colibri/c/vk_tier.c)), computed on GPU while the CPU streams cold experts in parallel.

---

## 2. GLM 5.3 in Colibrì: Model Breakdown

There are two separate models in the GLM-5.3 family supported by Colibrì:

| Metric | **GLM-5.3 (Flagship MoE)** | **GLM-5.3-Flash (Multimodal MoE)** |
| :--- | :--- | :--- |
| **Total Parameters** | **744 Billion** | **321 Billion** |
| **Architecture** | 78 layers, 256 routed experts (top-8), hidden 6144, intermediate 2048, MLA attention, DSA sparse indexer | 45 text layers + 1 MTP, 34 KDA linear attention + 11 DSA full attention layers with k-pooling, NoPE, mHC hyper-connections |
| **Engine Executable** | [`c/colibri.c`](file:///workspaces/colibri/c/colibri.c) (binary: `colibri`, alias `glm`) | [`c/glm53.c`](file:///workspaces/colibri/c/glm53.c) (binary: `glm53`) |
| **Catalog ID** | `glm-5.3` (family: `glm`) | `glm53` (family: `glm53`) |
| **Hugging Face Repo** | [`Justvugg/GLM-5.3-colibri-int4-g64`](https://huggingface.co/Justvugg/GLM-5.3-colibri-int4-g64) | [`Justvugg/GLM-5.3-Flash-colibri-int4-g64`](https://huggingface.co/Justvugg/GLM-5.3-Flash-colibri-int4-g64) |
| **Download Size** | **419.3 GB** (int4-gs64, no MTP head) | **194.7 GB** (converted container) |
| **Resident RAM** | ~9.9 GB | ~12.0 GB |
| **Modality** | Text / Code / Complex Reasoning | Text + Vision (24-block ViT tower) |

> [!IMPORTANT]
> **Quantization Format:** Always use group-scaled **`int4-gs64`** containers. Older per-row 4-bit quantizations degrade benchmark quality by ~9pp and cause infinite loops during reasoning turns. Both recommended repositories above use `int4-gs64`.

---

## 3. Host System Hardware Audit

Running hardware detection (`setup_hw.py`, `nvidia-smi`, `lsblk`, `nvme list`) confirmed:

- **CPU:** AMD Ryzen 9 9950X (16 physical cores, 32 threads, AVX-512, AVX_VNNI, AVX512_BF16).
- **RAM:** **98.1 GB DDR5** (72+ GB free). Far exceeds the 16–24 GB minimum, providing ample headroom for a massive in-memory expert cache.
- **GPUs:**
  - **GPU 0:** NVIDIA RTX PRO 6000 Blackwell Workstation Edition (103 GB GDDR7 VRAM, compute 12.0, driver 595.99.02).
  - **GPU 1:** NVIDIA GeForce RTX 5090 (34.2 GB GDDR7 VRAM, compute 12.0).
  - **Vulkan Status:** Vulkan 1.4.329 is active, reporting a **90.5 GB** memory budget on GPU 0.
- **Storage:** Two physical Samsung SSD 9100 PRO 4TB NVMe drives.

---

## 4. Dual-NVMe Discovery & Configuration

### The Initial State
- **`nvme0n1` (4TB):** System OS, root filesystem, docker container workspace (`/workspaces/colibri`). Free space: ~1.2 TB.
- **`nvme1n1` (4TB):** The secondary NVMe SSD was completely unpartitioned, raw, and unmounted.

### Actions Taken
1. **Partitioning & Formatting:**
   - Created GPT partition table on `/dev/nvme1n1`.
   - Created partition `/dev/nvme1n1p1` and formatted as `ext4` with label `colibri_models`.
2. **Mount Optimizations:**
   - Mounted with `noatime,nodiratime` to prevent access-time metadata write overhead during high-frequency streaming reads.
3. **Bandwidth Benchmarking:**
   - **`fio` Direct I/O:** **5,721 MiB/s (~6.0 GB/s)** sequential read, **4,395 MiB/s** sequential write.
   - **Colibrì `iobench`:** Tested with 19MB int4 expert blocks across 8 OpenMP threads with `O_DIRECT`:
     ```text
     O_DIRECT x8 threads: 64 reads x 19 MB = 1.3 GB in 0.24s -> 5.35 GB/s (3.7 effective ms/block)
     ```
   - *Result:* Loading an entire 19MB expert takes only **3.7 ms**, virtually eliminating the disk bottleneck.

---

## 5. Devcontainer vs. Host Mount Resolution

### The Problem
When testing from the host terminal (`tarfy@tarfy-System-Product-Name:`), running `df -h /models` resulted in:
```text
df: /models: No such file or directory
```
**Root Cause:**
- Docker containers have isolated mount namespaces (`rprivate` propagation).
- `.devcontainer/devcontainer.json` was configured to bind-mount the host folder `/mnt/models_fast/models` into container path `/models`.
- On the host, `/dev/nvme1n1p1` was unmounted, and `/models` only existed inside the container.

### The Host-Side Fix
1. **Mounted Secondary NVMe on Host:**
   ```bash
   mount -o noatime,nodiratime /dev/nvme1n1p1 /mnt/models_fast
   mkdir -p /mnt/models_fast/models /mnt/models_fast/hf_cache
   chmod -R 777 /mnt/models_fast
   ```
2. **Created Host Symlink:**
   ```bash
   ln -sfn /mnt/models_fast /models
   ```
3. **Persisted in Host `/etc/fstab`:**
   ```text
   UUID=dec24f4a-6705-4192-af43-5c6ac0f29b50 /mnt/models_fast ext4 noatime,nodiratime,errors=remount-ro 0 2
   ```
4. **Verification:**
   Both host and container now point to the identical 3.6 TB filesystem. Running `df -h /models` produces:
   ```text
   Filesystem      Size  Used Avail Use% Mounted on
   /dev/nvme1n1p1  3.6T   36K  3.6T   1% /mnt/models_fast  # (on host)
   /dev/nvme1n1p1  3.6T   36K  3.6T   1% /models           # (in container)
   ```

---

## 6. Build & Engine Compilation Fixes

### Shader Compilation Fixes
When building with `VK=1`, Makefile requires compiled SPIR-V shaders (`.spv`). Four shaders lacked pre-built binaries:
- `qmatmul_gate_up.comp`
- `attention_absorb.comp`
- `expert_act.comp` / `expert_act_v4.comp`
- `rmsnorm.comp`

These were compiled using `glslangValidator`:
```bash
glslangValidator -V --target-env vulkan1.2 c/shaders/qmatmul_gate_up.comp -o c/shaders/qmatmul_gate_up.spv
glslangValidator -V --target-env vulkan1.2 c/shaders/attention_absorb.comp -o c/shaders/attention_absorb.spv
glslangValidator -V --target-env vulkan1.2 c/shaders/expert_act.comp -o c/shaders/expert_act.spv
glslangValidator -V --target-env vulkan1.2 c/shaders/expert_act_v4.comp -o c/shaders/expert_act_v4.spv
glslangValidator -V --target-env vulkan1.2 c/shaders/rmsnorm.comp -o c/shaders/rmsnorm.spv
```

### Vulkan ICD Symlink
Fixed the missing driver manifest symlink:
```bash
ln -s /etc/vulkan/icd.d/nvidia_icd.json /usr/share/vulkan/icd.d/nvidia_icd.json
```

### Successful Engine Binaries
Both engines were compiled with native CPU vectorization and Vulkan acceleration:
```bash
make -C c colibri VK=1 ARCH=native   # For GLM-5.3 (744B)
make -C c glm53 VK=1 ARCH=native     # For GLM-5.3-Flash (321B)
gcc -O2 -fopenmp -I c c/iobench.c -o c/iobench # Diagnostic benchmark
```

---

## 7. Execution Runbook: Downloading and Running GLM-5.3

### Step 1: Download Model to Dedicated NVMe
Using `huggingface-cli` directly into `/models/glm-5.3`:
```bash
huggingface-cli download Justvugg/GLM-5.3-colibri-int4-g64 \
    --local-dir /models/glm-5.3 \
    --local-dir-use-symlinks False
```
*(Or use `python3 c/coli setup --model glm-5.3 --dir /models --backend vulkan --no-start`)*

### Step 2: Validate Model Files
```bash
python3 c/coli doctor --model /models/glm-5.3
```

### Step 3: Run Inference (Interactive Chat)
```bash
export COLI_VULKAN=1
export DISPLAY=
python3 c/coli chat --model /models/glm-5.3
```

### Step 4: Run Web Dashboard / Visualizer
```bash
export COLI_VULKAN=1
export DISPLAY=
python3 c/coli web --model /models/glm-5.3 --host 0.0.0.0 --port 8000
```
- Web UI: `http://127.0.0.1:8000/`

### Step 5: Run OpenAI / Anthropic API Server
```bash
export COLI_VULKAN=1
export DISPLAY=
python3 c/coli serve --model /models/glm-5.3 --host 0.0.0.0 --port 8000
```
- OpenAI Endpoint: `http://127.0.0.1:8000/v1/chat/completions`
- Anthropic Endpoint: `http://127.0.0.1:8000/v1/messages`

---

## 8. Optimal Runtime Knobs for This Workstation

With **103 GB VRAM** on RTX PRO 6000 and **98 GB RAM**, configure:
```bash
# Vulkan GPU acceleration on
export COLI_VULKAN=1

# Dense layers permanently resident on GPU
export COLI_VK_DENSE=1

# Layer-fused dense chains on GPU
export COLI_VK_CHAIN=1

# Allocate generous expert cache slots
export CAP=64
```
