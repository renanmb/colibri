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

### Phase 2: Shard Acquisition (Completed)
- [x] Initiated resumable multi-stream download:
  `hf download Justvugg/GLM-5.3-colibri-int4-g64 --local-dir /models/glm-5.3 --max-workers 8`
- [x] Monitored download progress and verified 141 shards (419.3 GB) on `/models/glm-5.3`.
- [x] Verified safetensors header and model integrity with `python3 c/coli doctor --model /models/glm-5.3` (All checks passed).

### Phase 3: Hardware Tuning & Verification (Completed)
- [x] Initial warm-up prompt executed (`COLI_VULKAN=1 python3 c/coli run --model /models/glm-5.3 --ngen 10 --no-think "Hello"`).
- [x] Verified Vulkan expert tier active on RTX PRO 6000 Blackwell (92.06 GB allocated, 4354 experts capacity).
- [x] Verified KV8 latent quantization active (~3.9x less KV RAM).
- [x] Verified generation output: "Hello! How can I help you today?" generated cleanly with 60.1% expert hit rate on first cold pass.

### Phase 4: Production Serving (Completed)
- [x] Started background server with `coli start --background --no-browser` on port 8000.
- [x] Verified OpenAI API endpoints (`/v1/chat/completions`) and web dashboard (`http://127.0.0.1:8000/`).
- [x] Model `glm-5.2-colibri` serving live with Vulkan GPU tiering on RTX PRO 6000 and direct NVMe storage streaming.
- [x] Enabled dual-GPU expert pooling (`COLI_VK_DEV2=auto`): pooled RTX PRO 6000 (3,888 experts) + RTX 5090 (1,475 experts) for 5,363 resident VRAM experts (~113 GB VRAM).
- [x] Measured empirical streaming benchmarks: TTFT 12.17s–15.12s, pure generation 0.52–0.55 tok/s.
- [x] Configured Hermes Agent CLI integration and documented prompt tuning and BIOS optimizations in `.agents/references/notes/wrapup_performance_and_bios_tuning_guide.md`.


