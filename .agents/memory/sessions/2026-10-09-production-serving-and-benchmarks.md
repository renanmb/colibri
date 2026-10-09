# Session Summary: 2026-10-09 (Production Serving, Dual-GPU & Benchmarks)

## Objectives
- Transition GLM-5.3 744B local deployment to Phase 4 (Production Serving).
- Enable and verify OpenAI and Anthropic compatible HTTP API endpoints.
- Configure Hermes Agent CLI to use the local model.
- Activate multi-GPU Vulkan expert tiering (RTX PRO 6000 + RTX 5090).
- Empirically measure Time to First Token (TTFT) and pure generation Tokens Per Second (TPS).
- Analyze prompt tuning tradeoffs and document BIOS hardware optimizations for NVMe and GPUs.

## Accomplishments
1. **Model Download & Integrity Verification (Phase 2):**
   - Resumed and completed downloading all 141 shards (419.3 GB) of `Justvugg/GLM-5.3-colibri-int4-g64` directly into `/models/glm-5.3`.
   - Verified safetensors headers and tensor layouts via `python3 c/coli doctor --model /models/glm-5.3` (100% pass).

2. **Phase 3 Warm-up Verification:**
   - Ran initial forward pass test prompt (`COLI_VULKAN=1 python3 c/coli run --model /models/glm-5.3 --ngen 10 --no-think "Hello"`).
   - Confirmed expert tier allocation on RTX PRO 6000 and clean generation ("Hello! How can I help you today?").

3. **Phase 4 Production Serving:**
   - Started persistent background server on `http://127.0.0.1:8000/` (OpenAI base: `http://127.0.0.1:8000/v1`, Model ID: `glm-5.2-colibri`).
   - Verified live OpenAI `/v1/chat/completions` and health endpoints.

4. **Multi-GPU Vulkan Pooling (`COLI_VK_DEV2=auto`):**
   - Activated both GPUs concurrently:
     - **GPU 0 (RTX PRO 6000 Blackwell, 103 GB VRAM):** 78-layer dense trunk (8.63 GiB) + 3,888 routed experts in 82.34 GiB VRAM.
     - **GPU 1 (RTX 5090, 32 GB VRAM):** 1,475 routed experts in 30.73 GiB VRAM.
     - **Total VRAM Resident Experts:** 5,363 active experts (~113 GB VRAM total).

5. **Empirical Streaming Benchmarking:**
   - Created and ran automated benchmark (`.agents/scratch/benchmark_inference.py`) with SSE streaming timings:
     - Short prompt (10 tokens): TTFT = 12.17s.
     - Medium prompt (50 tokens): TTFT = 14.66s, pure generation TPS = 0.52 tok/s.
     - Code prompt (100 tokens): TTFT = 15.12s, pure generation TPS = 0.55 tok/s.
   - Dual-GPU workload split observed: GPU 0 processed 12,036 experts, GPU 1 processed 8,807 experts, NVMe streamed 23,257 cold experts at 7 GB/s without CPU stalls.

6. **Hermes Agent CLI Integration & Prompt Tuning:**
   - Configured Hermes in `~/.hermes/config.yaml` to route to `http://127.0.0.1:8000/v1` via `custom:colibri`.
   - Identified prompt tax: Hermes by default injected 24 tools and 53 skills (~14,000 prompt tokens), which turns MoE prefill into an all-expert dense workload.
   - Optimized toolsets via `platform_toolsets.cli: [terminal, file]`, reducing prompt from ~14k to ~6k tokens and speeding up prefill by ~5×.
   - Resolved stuck background test tasks (`task-909`, `task-964`) and cleared server queue.

7. **Documentation & Tuning Guides Created:**
   - `.agents/references/notes/using_glm53_with_hermes.md`: Complete Hermes integration runbook.
   - `.agents/references/notes/hardware_architecture.md`: Updated with dual-GPU topology and benchmark metrics.
   - `.agents/references/notes/wrapup_performance_and_bios_tuning_guide.md`: Comprehensive wrapup guide covering model scale, benchmarks, BIOS NVMe/GPU tuning, and agent prompt tuning.
   - `.agents/references/plans/glm53_deployment_plan.md`: Updated to mark Phase 4 complete with all milestones.

## Active State
- **Server Command:** `COLI_VK_DEV2=auto COLI_VK_CHAIN_ROWS=512 KV8=0 python3 c/coli start --background --no-browser`
- **Server Status:** Ready, dual-GPU enabled, zero active tasks in queue.
