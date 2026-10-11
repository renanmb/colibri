#!/usr/bin/env bash
# ==============================================================================
# Workstation Health & DisplayPort Signal Stability Scanner
# ==============================================================================
# Diagnoses GPU power transients, DisplayPort link state, PCIe bus integrity,
# and CPU bus lock contention on dual-GPU (RTX PRO 6000 + RTX 5090) systems.
# ==============================================================================

set -euo pipefail

echo "========================================================================"
echo "          WORKSTATION HEALTH & DISPLAYPORT STABILITY SCANNER            "
echo "========================================================================"
date -u +"Date (UTC): %Y-%m-%dT%H:%M:%SZ"
echo ""

# 1. Display Connector & Monitor Status
echo "── [1/5] Display Connector & EDID Negotiation ──"
if [ -d "/sys/class/drm/card0-DP-3" ]; then
    DP_STATUS=$(cat /sys/class/drm/card0-DP-3/status 2>/dev/null || echo "unknown")
    DP_ENABLED=$(cat /sys/class/drm/card0-DP-3/enabled 2>/dev/null || echo "unknown")
    DP_DPMS=$(cat /sys/class/drm/card0-DP-3/dpms 2>/dev/null || echo "unknown")
    echo "  Connector:   card0-DP-3 (GPU 0 - RTX PRO 6000 Blackwell)"
    echo "  Status:      ${DP_STATUS}"
    echo "  Mode:        ${DP_ENABLED}"
    echo "  Power State: ${DP_DPMS}"
    echo "  Top Modes:"
    head -n 3 /sys/class/drm/card0-DP-3/modes 2>/dev/null | sed 's/^/    - /' || echo "    - none"
else
    echo "  card0-DP-3 connector not found in sysfs."
fi
echo ""

# 2. GPU Power Limits, Current Draw & Throttling Flags
echo "── [2/5] GPU Power Telemetry & Throttling Flags ──"
nvidia-smi --query-gpu=index,name,power.draw,power.limit,temperature.gpu,clocks_event_reasons.hw_power_brake_slowdown,clocks_event_reasons.sw_power_cap,clocks_event_reasons.hw_slowdown --format=csv
echo ""

# 3. GPU Clocks & Memory State
echo "── [3/5] GPU Clocks & P-State ──"
nvidia-smi --query-gpu=index,name,clocks.current.graphics,clocks.current.memory,pstate --format=csv
echo ""

# 4. PCIe Link Speed & Signal Integrity Replays
echo "── [4/5] PCIe Generation, Width & Replay Counters ──"
nvidia-smi --query-gpu=index,name,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv
echo ""
echo "  PCIe Replay Packet Errors (GPU 0):"
nvidia-smi -q -i 0 | grep -E "Replays Since Reset|Replay Number Rollovers" | sed 's/^/  /'
echo ""

# 5. Kernel Bus Lock & Buffer Overrun Traps
echo "── [5/5] Kernel Ring Buffer Audit (Split Locks & Overruns) ──"
BUS_LOCKS=$(dmesg -T 2>/dev/null | grep -c "bus_lock trap" || true)
OVERRUNS=$(dmesg -T 2>/dev/null | grep -c "buffer overrun event" || true)
echo "  x86 Split Lock Traps:    ${BUS_LOCKS} events detected in dmesg"
echo "  USB Buffer Overruns:     ${OVERRUNS} events detected in dmesg"
if [ "${BUS_LOCKS}" -gt 0 ]; then
    echo "  Latest Split Lock Event:"
    dmesg -T 2>/dev/null | grep "bus_lock trap" | tail -n 1 | sed 's/^/    /'
fi
echo ""

echo "========================================================================"
echo "Scan complete. If DisplayPort loses signal during gaming:"
echo "1. Run 'nvidia-smi -rmc' to release forced GDDR memory locks."
echo "2. Cap in-game framerate to monitor refresh - 3 FPS (e.g. 141 FPS)."
echo "3. Ensure independent 12V-2x6 / 8-pin power leads from PSU (no daisy-chain)."
echo "========================================================================"
