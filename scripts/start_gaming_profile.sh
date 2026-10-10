#!/usr/bin/env bash
# ==============================================================================
# Colibrì GLM-5.3 Gaming & Vibe-Coding Profile Launcher
# ==============================================================================
# Hardware Protections:
# - Reserves 20+ GB of VRAM on GPU 0 (RTX PRO 6000) for 4K games, DirectX/Vulkan & display.
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
  COLI_MODEL_MIRROR=/workspaces/colibri/models_mirror/glm-5.3 \
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
  COLI_VK_TIER_STREAM_ROWS=2 \
  COLI_VK_CHAIN_ROWS=256 \
  OMP_NUM_THREADS=8 \
  COLI_KV_SLOTS=2 \
  COLI_KV_SHARE=1 \
  COLI_VK_DEV2=auto \
  COLI_VK_EXPERTS2=1100 \
  COLI_VK_RESERVE2_GB=6.0 \
  python3 c/coli start --background --no-browser

echo "[Gaming Profile] Server started in background."
echo "[Gaming Profile] Run 'vibe-gaming chat' or 'vibe-gaming' to start vibe coding!"
