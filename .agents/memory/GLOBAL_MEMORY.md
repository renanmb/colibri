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
- **CPUs:** AMD Ryzen 9 9950X (AVX-512 supported; use `ARCH=native` for all compilations).
- **GPUs:** Dual Blackwell series GPUs (RTX PRO 6000 103GB + RTX 5090 34GB).
- **Vulkan Driver:** NVIDIA 595.99.02 (Vulkan 1.4 working with headless `DISPLAY=`).
- **Engine Binaries:**
  - `c/colibri` is compiled with `VK=1 ARCH=native` for GLM-5.2 and GLM-5.3.
  - `c/glm53` is compiled with `VK=1 ARCH=native` for GLM-5.3-Flash.
  - `c/iobench` is compiled for streaming benchmark validation.

---

## 3. Active Goal & Decisions
- **Target Model:** GLM-5.3 744B (`Justvugg/GLM-5.3-colibri-int4-g64`, 419.3 GB download).
- **Container Format:** Group-scaled `int4-gs64` without MTP head.
- **Second NVMe:** Formatted with ext4, `noatime,nodiratime`, tested at ~6.0 GB/s direct read.
