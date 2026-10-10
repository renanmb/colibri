# Gaming & Vibe-Coding Profile Guide (GLM-5.3 744B)

This guide documents the configuration, resource budgeting, and execution steps for running **GLM-5.3 744B** locally while simultaneously playing modern AAA games on the host workstation.

---

## 1. Resource Allocation & Isolation Strategy

When playing games while running a 744B MoE model in the background, the primary risks are **VRAM contention (leading to game crashes / DirectX device lost)**, **CPU thread starvation (causing game micro-stutters and frame drops)**, and **system RAM exhaustion**.

| Resource | Total Host Capacity | Colibrì Gaming Profile Allocation | Reserved for Gaming & OS | Protection Mechanism |
|---|---|---|---|---|
| **GPU 0: RTX PRO 6000 VRAM** | 97.8 GB (~96 GiB) | ~41.5 GB allocated (dense trunk + ~3,065 experts) | **~56.3 GB Free** (Minimum 14.0 GB hard reserve guaranteed) | `COLI_VK_TIER_RESERVE_GB=14.0` |
| **GPU 1: RTX 5090 VRAM** | 32.6 GB | ~30.3 GB (1,474 resident experts) | N/A (Dedicated to LLM compute offload) | `COLI_VK_DEV2=auto` |
| **Host System RAM** | 98.1 GB | ~29.1 GB resident / active | **~69.0 GB Free & Available** | `RAM_GB=48.0` + `CAP_RAISE=0` |
| **AMD Ryzen 9 9950X CPU** | 16 Cores / 32 Threads | 8 Threads | **8 Physical Cores / 16 Threads Dedicated to Game** | `OMP_NUM_THREADS=8` |
| **Process CPU Scheduling** | Normal priority | `nice -n 12` | Highest priority for game physics & render threads | Linux process preemption |

---

## 2. Server Configuration

A dedicated launcher script is located at [scripts/start_gaming_profile.sh](file:///workspaces/colibri/scripts/start_gaming_profile.sh):

```bash
#!/usr/bin/env bash
nice -n 12 env \
  RAM_GB=48 \
  COLI_VK_TIER_RESERVE_GB=14.0 \
  OMP_NUM_THREADS=8 \
  COLI_KV_SHARE=1 \
  COLI_VK_DEV2=auto \
  COLI_VK_CHAIN_ROWS=512 \
  KV8=0 \
  python3 c/coli start --background --no-browser
```

### Key Levers Explained:
- `COLI_VK_TIER_RESERVE_GB=14.0`: Guarantees that at least 14 GiB of VRAM on GPU 0 is never touched by the expert tier, leaving abundant headroom for game textures, display buffers, and DirectX 12 / Vulkan allocations.
- `RAM_GB=48`: Caps Colibrì's total projected RAM footprint, ensuring ~50–69 GB of host RAM remains available for gaming.
- `OMP_NUM_THREADS=8`: Prevents CPU prefill bursts from saturating all 32 threads of the Ryzen 9 9950X.
- `nice -n 12`: Gives Colibrì lower OS CPU priority than the game, ensuring zero impact on 1% frametime lows.
- `COLI_VK_DEV2=auto`: Utilizes the second GPU (RTX 5090) to house 1,474 routed experts, keeping 4,539+ active experts in VRAM despite the GPU 0 reserve.

---

## 3. Dedicated Hermes Profile: `vibe-gaming`

A dedicated Hermes profile was created at `/root/.hermes/profiles/vibe-gaming` with its own wrapper script at `/root/.local/bin/vibe-gaming`.

### Profile Optimizations Applied:
1. **Zero Skill Bloat:**
   - Pruned all 58 bundled consumer/media skills via `hermes -p vibe-gaming skills opt-out --remove --yes`.
   - Only workspace-local engineering skills load when relevant.
2. **Clamped Reasoning:**
   - Configured `agent.reasoning_effort: low` to eliminate 20+ minute thinking pauses during tool calls.
3. **Live Streaming:**
   - Configured `streaming.enabled: true` and `display.streaming: true` so tokens stream in real time.
4. **Vibe-Coding `SOUL.md` Directive:**
   - Configured `/root/.hermes/profiles/vibe-gaming/SOUL.md` to mandate instant tool execution, extreme brevity, and clean shell output without conversational preamble.
5. **Context Protection:**
   - `compression.threshold: 0.35`, `compression.proactive_prune_tokens: 1024`, `protect_last_n: 6`.

---

## 4. How to Use the Gaming & Vibe-Coding Profile

### Step 1: Start the Server in Gaming Mode
```bash
/workspaces/colibri/scripts/start_gaming_profile.sh
```

### Step 2: Verify Memory Isolation
```bash
nvidia-smi --query-gpu=index,name,memory.total,memory.free,memory.used --format=csv
```
*Expected: GPU 0 has 50–57 GB free (far exceeding the 12 GB requirement).*

### Step 3: Launch Interactive Vibe-Coding
Simply run the profile alias directly:
```bash
vibe-gaming
```
Or start an interactive chat session:
```bash
vibe-gaming chat
```
Or run a fast one-shot query:
```bash
vibe-gaming -z "Create a fast python benchmark for socket ping latency"
```

---

## 5. Switching Back to Maximum Performance Mode

When done gaming and seeking full-scale multi-turn throughput:
```bash
python3 c/coli stop
COLI_KV_SHARE=1 COLI_VK_DEV2=auto COLI_VK_CHAIN_ROWS=512 KV8=0 python3 c/coli start --background --no-browser
hermes
```
