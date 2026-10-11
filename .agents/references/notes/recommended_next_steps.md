# Recommended Next Steps: Production Vibe-Coding & System Evolution

**Document Path:** `.agents/references/notes/recommended_next_steps.md`  
**Date:** October 11, 2026  
**Status:** Post-Testing Milestone Roadmap  
**Related Reference:** [`.agents/references/plans/hermes_agent_multi_phase_testing_plan.md`](file:///workspaces/colibri/.agents/references/plans/hermes_agent_multi_phase_testing_plan.md)

---

## 1. Executive Summary: Milestone Completion

With the conclusion and verification of all five testing phases in the [Hermes Agent Multi-Phase Testing Plan](file:///workspaces/colibri/.agents/references/plans/hermes_agent_multi_phase_testing_plan.md), the entire local stack (**Colibrì C engine + GLM-5.3 744B MoE + Dual-GPU Vulkan tiering + Dual-NVMe storage streaming + Hermes Agent harness**) has been proven reliable, resource-isolated, and production-ready:

* **15 of 15 Tests Verified:** 100% pass rate across core primitives, autonomous engineering loops, stateful interactive UX, long-context scaling (>10k tokens), concurrent 3D rendering stress, and telemetry line rates.
* **Workstation Isolation Guaranteed:** 24.4 GiB free VRAM permanently unallocated on GPU 0; 8 CPU worker threads strictly bounded to `nice -n 12`.
* **Zero Driver Instability:** Persistent P0 clock locking (14,001 MHz) and DMA staging (`COLI_VK_STAGED=1`) completely eliminate BAR1 exhaustion and `VK_ERROR_DEVICE_LOST`.

The infrastructure validation phase is complete. Below are the **four recommended strategic paths** for operationalizing, accelerating, and expanding the system.

---

## 2. Strategic Path 1: Daily Production Pair-Programming ("Vibe-Coding")

The primary objective is transitioning from infrastructure testing to actual software development using `vibe-gaming`.

### Recommended Daily Workflows

#### 1. Interactive Named Sessions (High Warm Cache Hit Rate)
Always use persistent named sessions via `-c` to exploit warm Radix KV prefix reuse:
```bash
vibe-gaming chat -c "feature-jwt-auth"
```
* **Why:** Turn 1 incurs the one-time cold prefill cost (~21m) to lock the 3,764-token system prompt and tool definitions into `KV Slot 0`. All subsequent turns (Turn 2 through Turn N) prefill only the new turn delta (15–150 tokens), responding in **10 seconds to 2 minutes** (a **13× to 358× speedup**).
* **Live Streaming:** Real-time `<think>` chain-of-thought streaming is active, giving immediate visibility into the model's architectural reasoning before tools execute.

#### 2. Targeted Autonomous One-Shots
For discrete unit edits, bug fixes, or test driver creation:
```bash
vibe-gaming -z "Inspect tests/test_matrix.py, fix the assertion on line 6, and verify via terminal."
```
* Hermes will read the target file, apply a precision fuzzy patch, execute the test in a sub-shell, verify stdout, and exit cleanly.

#### 3. Best Practices for Context Management
* **Keep Retrieval Compact:** Avoid instructing the agent to dump thousands of lines of raw source code into the prompt. Direct it toward specific symbols, functions, or line ranges (e.g. `read_file` lines 1–60).
* **Operational Window:** Maintain active session context within the **3,000 to 16,000 token sweet spot**. This ensures turn turnaround remains under 2–8 minutes while staying well within GPU 0 VRAM margins.

---

## 3. Strategic Path 2: Mirror Remaining 86 Shards to Maximize Dual-NVMe Throughput

Currently, **55 hot shards** are mirrored on `/dev/nvme0` (`/workspaces/colibri/models_mirror/glm-5.3`), which enabled our measured **15.19 GB/s peak throughput**. The remaining 86 shards still stream exclusively from `/dev/nvme1` (the bifurcated Gen 5 x2 slot).

### Storage Headroom
* `/dev/nvme0` (`/workspaces/colibri`): **1.2 TB free space** (Full Gen 5 x4, 10.4–14.2 GB/s line rate).
* Shards to mirror: **86 safetensors files (~250 GB)**.

### Execution Procedure
To stripe 100% of GLM-5.3 cold experts across both NVMe controllers:
```bash
# Copy remaining model shards to the fast nvme0 mirror
rsync -av --ignore-existing /models/glm-5.3/*.safetensors /workspaces/colibri/models_mirror/glm-5.3/
```

### Anticipated Impact
* **100% Dual-Drive Striping:** Every cold expert load will be split evenly across the x4 and x2 drives.
* **Reduced Cold Prefill:** Turn 1 cold prefill is projected to decrease from **~21 minutes down to ~12–15 minutes**.

---

## 4. Strategic Path 3: Deploy GLM-5.3-Flash for Instant Sub-Second Tasks

While GLM-5.3 (744B) is the primary heavy-duty reasoning engine, the smaller **GLM-5.3-Flash** model (documented in the `colibri-glm` skill) is an ultra-fast companion.

### Architectural Fit
| Characteristic | GLM-5.3 (744B MoE) | GLM-5.3-Flash |
|---|---|---|
| **Primary Role** | Deep architecture, complex refactoring, multi-turn bug loops | Quick triage, linting, syntax lookups, commit messages |
| **Placement** | Hybrid (94.4 GB in VRAM + NVMe streaming) | 100% Resident in VRAM (zero NVMe streaming required) |
| **Response Latency** | 10s–2m warm / ~21m cold | **Sub-second (instant, 30–60 tokens/sec)** |
| **VRAM Footprint** | 73.4 GiB (GPU 0) + 22.6 GiB (GPU 1) | ~8–12 GiB |

### Multi-Model Delegation Workflow
Configure Hermes to use Flash for auxiliary background tasks (e.g., commit message generation, web extracts, title generation, or quick research subagents), while keeping the main conversational session pinned to GLM-5.3 744B.

---

## 5. Strategic Path 4: Workstation Automation (`systemd` Service)

Automate the Colibrì background engine so the workstation boots directly into a ready-to-serve state without manual terminal steps.

### Systemd User Unit (`~/.config/systemd/user/colibri-gaming.service`)

```ini
[Unit]
Description=Colibri GLM-5.3 Gaming Inference Server
After=network.target

[Service]
Type=forking
WorkingDirectory=/workspaces/colibri
ExecStart=/workspaces/colibri/scripts/start_gaming_profile.sh
ExecStop=/usr/bin/python3 /workspaces/colibri/c/coli stop
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=default.target
```

### Benefits
* GPU clocks locked to **14,001 MHz** and driver persistence mode set automatically at boot.
* Colibrì server is always warm and listening on `127.0.0.1:8000`.
* Launching `vibe-gaming chat` instantly connects to the running engine.

---

## 6. Actionable Next Steps Checklist

| Priority | Strategic Path | Action Item | Estimated Effort |
|:---:|---|---|:---:|
| **P1** | **Path 1: Real-World Usage** | Launch a named session on your target feature or codebase (`vibe-gaming chat -c "<name>"`) | Immediate |
| **P2** | **Path 2: NVMe Striping** | Rsync remaining 86 shards to `/workspaces/colibri/models_mirror/glm-5.3/` to achieve 100% striped disk I/O | ~15–20 min transfer |
| **P3** | **Path 4: Automation** | Install `systemd` user service for zero-touch boot startup and automatic GPU clock locking | ~5 min setup |
| **P4** | **Path 3: Multi-Model** | Download and configure GLM-5.3-Flash as a sub-second companion agent in Hermes | ~30 min setup |
