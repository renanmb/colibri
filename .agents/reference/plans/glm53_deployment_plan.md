# Deployment Plan: Running GLM-5.3 Locally with Colibrì

This plan outlines the end-to-end execution path for downloading, verifying, tuning, and serving the GLM-5.3 744B model locally on this machine.

---

## 1. Objectives & Hardware Allocation

- **Model:** GLM-5.3 (`Justvugg/GLM-5.3-colibri-int4-g64`, 744B parameters, int4-gs64, ~419 GB).
- **Storage Target:** `/models/glm-5.3` on `/dev/nvme1n1p1` (Samsung SSD 9100 PRO 4TB, measured ~6.0 GB/s read bandwidth).
- **RAM Allocation:** 98.1 GB system RAM (dense resident weights consume ~9.9 GB; remaining ~60+ GB acts as LRU expert cache).
- **GPU Tiering:** NVIDIA RTX PRO 6000 Blackwell (103 GB VRAM) via Vulkan 1.4 for the expert tier and layer-fused dense chains.

---

## 2. Execution Phases

### Phase 1: Environment Readiness (Completed)
- [x] Host and Devcontainer filesystem alignment:
  - Formatted `/dev/nvme1n1p1` (ext4 with `noatime,nodiratime`).
  - Mounted on host `/mnt/models_fast` with symlink `/models -> /mnt/models_fast`.
  - Mounted in container at `/models`.
  - Added entry to host `/etc/fstab` with UUID `dec24f4a-6705-4192-af43-5c6ac0f29b50`.
- [x] Compile pure-C inference engines:
  - Built `colibri` with `VK=1 ARCH=native`.
  - Built `glm53` with `VK=1 ARCH=native`.
  - Built `iobench` diagnostic tool.
- [x] Verified Vulkan ICD loader and NVIDIA 595.99.02 driver compatibility.

### Phase 2: Shard Acquisition (Pending User Confirmation)
- [ ] Initiate resumable multi-stream download:
  ```bash
  huggingface-cli download Justvugg/GLM-5.3-colibri-int4-g64 \
      --local-dir /models/glm-5.3 \
      --local-dir-use-symlinks False
  ```
- [ ] Monitor download progress and disk space utilization on `/models`.
- [ ] Verify SHA-256 / safetensors header integrity with `python3 c/coli doctor --model /models/glm-5.3`.

### Phase 3: Hardware Tuning & Profiling
- [ ] Initial warm-up prompt run to generate `.coli_usage` routing history.
- [ ] Tune Vulkan expert tier size (`COLI_VK_TIER_RAM_GB`) and dense chain (`COLI_VK_CHAIN=1`).
- [ ] Measure baseline token generation rate (tok/s) on standard benchmark prompts.

### Phase 4: Production Serving
- [ ] Start background server with `coli serve` on port 8000.
- [ ] Connect agentic workflows and developer clients via standard OpenAI/Anthropic APIs.
