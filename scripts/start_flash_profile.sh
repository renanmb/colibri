#!/usr/bin/env bash
# ==============================================================================
# Colibrì GLM-5.3-Flash Gaming & Vibe-Coding Profile Launcher
# ==============================================================================
# Hardware Protections & Optimizations:
# - Model: GLM-5.3-Flash (321B Multimodal MoE, 182 GB on /models/glm-5.3-flash).
# - Reserves 25+ GB of VRAM on GPU 0 (RTX PRO 6000) for 4K gaming, DirectX/Vulkan & display.
# - Reserves 10+ GB of VRAM on GPU 1 (RTX 5090) with staged DMA uploads (COLI_VK_STAGED=1).
# - Retains native FP32 KV cache (KV8=0) and multi-slot Radix sharing (COLI_KV_SLOTS=2, COLI_KV_SHARE=1).
# - Limits CPU OpenMP thread consumption to 8 threads (leaving 8 cores / 16 threads for games).
# - Launches with low OS priority (nice -n 12) to ensure game render loops are never preempted.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[Flash Profile] Stopping any running server..."
python3 c/coli stop 2>/dev/null || true

echo "[Flash Profile] Locking GPU clocks & setting persistence mode..."
nvidia-smi -pm 1 >/dev/null 2>&1 || true
nvidia-smi -lmc 14001,14001 >/dev/null 2>&1 || true
nvidia-smi -lgc 2100,2850 >/dev/null 2>&1 || true

echo "[Flash Profile] Launching tuned Colibrì background server for GLM-5.3-Flash..."
nice -n 12 env \
  DISPLAY= \
  COLI_VULKAN=1 \
  COLI_MODEL=/models/glm-5.3-flash \
  COLI_VRAM_CACHE_MB=105000 \
  CTX=65536 \
  GLM53_MAXT=65536 \
  KV8=0 \
  GLM53_EXPERT_GB=20.0 \
  RAM_GB=40.0 \
  DIRECT=1 \
  PIPE=1 \
  PIPE_WORKERS=16 \
  COLI_VK_STAGED=1 \
  COLI_VK_TIER_GB=76.0 \
  COLI_VK_TIER_RESERVE_GB=2.0 \
  COLI_VK_TIER_STREAM_SLOTS=16 \
  COLI_VK_TIER_STREAM_HALF=64 \
  COLI_VK_TIER_STREAM_ROWS=2 \
  COLI_VK_CHAIN_ROWS=128 \
  OMP_NUM_THREADS=8 \
  COLI_KV_SLOTS=2 \
  COLI_KV_SHARE=1 \
  COLI_VK_DEV2=auto \
  COLI_VK_EXPERTS2=1800 \
  COLI_VK_RESERVE2_GB=6.0 \
  python3 c/coli start --background --no-browser

echo "[Flash Profile] Background daemon started."
echo "[Flash Profile] Checking readiness..."
python3 c/coli status
