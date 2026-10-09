# Agent Global Memory

*Last Updated: 2026-10-09*

---

## 1. Operating Environment Invariants
- **Container Context:** Execution is happening inside a Linux Docker Devcontainer.
- **Host User:** `tarfy@tarfy-System-Product-Name`.
- **Mount Synchronization:**
  - Host path `/mnt/models_fast` is backed by the second 4TB NVMe drive (`/dev/nvme1n1p1`).
  - Host has a symlink `/models` pointing to `/mnt/models_fast`.
  - Inside the devcontainer, `/models` maps directly to this filesystem.
  - Never download models to `/root` or `/workspaces` — always store them in `/models`!

---

## 2. Hardware Capabilities & Engine Status
- **CPUs:** AMD Ryzen 9 9950X (AVX-512 supported; compiled with `ARCH=native`).
- **GPUs:** Dual NVIDIA series GPUs:
  - GPU 0: RTX PRO 6000 Blackwell (103 GB VRAM).
  - GPU 1: RTX 5090 (32 GB VRAM).
- **Vulkan Driver:** NVIDIA 595.99.02 (Vulkan 1.4 working with headless `DISPLAY=`).
- **Engine Binaries:**
  - `c/colibri` is compiled with `VK=1 ARCH=native` for GLM-5.2 and GLM-5.3.
  - `c/glm53` is compiled with `VK=1 ARCH=native` for GLM-5.3-Flash.
  - `c/iobench` is compiled for streaming benchmark validation.

---

## 3. Active Goal & Decisions
- **Target Model:** GLM-5.3 744B (`Justvugg/GLM-5.3-colibri-int4-g64`, 419.3 GB download, 141 shards on `/models/glm-5.3`).
- **Container Format:** Group-scaled `int4-gs64` without MTP head.
- **Second NVMe:** Formatted with ext4, `noatime,nodiratime`, tested at ~6.0-7.0 GB/s direct random read (2.8 ms per 19MB expert block).
- **Production Server:** Running in background (PID 36484 / engine PID 36486) on `http://127.0.0.1:8000/`.
  - **Launch Command:** `COLI_VK_DEV2=auto COLI_VK_CHAIN_ROWS=512 KV8=0 python3 c/coli start --background --no-browser`
  - **OpenAI API:** `http://127.0.0.1:8000/v1` (Model ID: `glm-5.2-colibri`)
  - **Anthropic API:** `http://127.0.0.1:8000`
  - **Dual-GPU Resident Experts:** 5,363 active experts pooled across both GPUs:
    - GPU 0 (RTX PRO 6000): 78-layer dense trunk (8.63 GiB) + 3,888 routed experts in 82.34 GiB VRAM.
    - GPU 1 (RTX 5090): 1,475 routed experts in 30.73 GiB VRAM.
  - **Empirical Benchmarks:** TTFT = 12-15s, pure generation TPS = ~0.52-0.55 tok/s (streaming via NVMe + dual GPU).
- **Hermes Agent Integration:** Configured in `~/.hermes/config.yaml` using `custom:colibri`. CLI toolsets trimmed to `[terminal, file]` to minimize prefill prompt tax.


