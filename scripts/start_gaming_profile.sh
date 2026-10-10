#!/usr/bin/env bash
# ==============================================================================
# Colibrì GLM-5.3 Gaming & Vibe-Coding Profile Launcher
# ==============================================================================
# Hardware Protections:
# - Reserves 14+ GB of VRAM on GPU 0 (RTX PRO 6000) for games, DirectX/Vulkan & display.
# - Leaves ~50+ GB of host system RAM completely free for game processes.
# - Limits CPU OpenMP thread consumption to 8 threads (leaving 8 cores / 16 threads for games).
# - Launches with low OS priority (nice -n 12) to ensure game render loops are never preempted.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[Gaming Profile] Stopping any running server..."
python3 c/coli stop 2>/dev/null || true

echo "[Gaming Profile] Launching tuned Colibrì background server..."
nice -n 12 env \
  RAM_GB=48 \
  COLI_VK_TIER_RESERVE_GB=10.0 \
  COLI_VK_TIER_STREAM_SLOTS=16 \
  OMP_NUM_THREADS=8 \
  COLI_KV_SHARE=1 \
  COLI_VK_DEV2=auto \
  COLI_VK_CHAIN_ROWS=512 \
  KV8=0 \
  python3 c/coli start --background --no-browser

echo "[Gaming Profile] Server started in background."
echo "[Gaming Profile] Run 'vibe-gaming chat' or 'vibe-gaming' to start vibe coding!"
