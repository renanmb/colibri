# Hardware Architecture & Environment Reference

## System Hardware Topology

```text
Host System: Ubuntu 22.04 LTS (Kernel 6.8.0-something / 595.99.02 NVIDIA driver)
CPU: AMD Ryzen 9 9950X (16 Cores, 32 Threads, AVX-512, AVX_VNNI, AVX512_BF16)
Memory: 98.1 GB DDR5 (72+ GB free)

Storage Architecture:
├── NVMe 0: Samsung SSD 9100 PRO 4TB (/dev/nvme0n1)
│   ├── Partition 1: 512 MB EFI System Partition (/boot/efi)
│   └── Partition 2: 3.6 TB Root Filesystem (/)
│       ├── Host OS, Docker images, user documents
│       └── Devcontainer Workspace (/workspaces/colibri)
└── NVMe 1: Samsung SSD 9100 PRO 4TB (/dev/nvme1n1)
    └── Partition 1: 3.6 TB Dedicated Models Volume (/dev/nvme1n1p1)
        ├── Filesystem: ext4 (mount options: noatime, nodiratime)
        ├── UUID: dec24f4a-6705-4192-af43-5c6ac0f29b50
        ├── Host Mount: /mnt/models_fast  (with host symlink: /models -> /mnt/models_fast)
        ├── Container Mount: /models
        └── Measured Performance: 5,721 MiB/s (~6.0 GB/s) sequential read, 3.7 ms expert load

GPU Acceleration Topology:
├── GPU 0: NVIDIA RTX PRO 6000 Blackwell Workstation Edition
│   ├── VRAM: 103 GB GDDR7 (ECC)
│   ├── Compute Capability: 12.0 (Blackwell architecture)
│   └── Vulkan Budget: 90.5 GB available device heap
└── GPU 1: NVIDIA GeForce RTX 5090
    ├── VRAM: 34.2 GB GDDR7
    └── Compute Capability: 12.0
```

---

## Devcontainer Mount Mechanics

The development container runs with `--privileged` and bind-mounts docker socket.

Crucial mount mappings:
1. **Container `/models` $\leftrightarrow$ Host `/mnt/models_fast`**:
   - The second NVMe (`/dev/nvme1n1p1`) is mounted on the host at `/mnt/models_fast`.
   - On the host, a convenience symlink `/models -> /mnt/models_fast` ensures identical paths.
   - Inside the container, `/models` directly accesses this 3.6 TB volume.
2. **Container `/root/.cache/huggingface` $\leftrightarrow$ Host `/mnt/models_fast/hf_cache`**:
   - Hugging Face cache downloads are routed directly to the second NVMe drive.
3. **Vulkan Multi-GPU Pooling:**
   - Primary Device (`GPU 0`): RTX PRO 6000 (Dense trunk 8.6 GiB + 3,888 expert slots in 82.3 GiB VRAM).
   - Secondary Device (`GPU 1`): RTX 5090 (1,475 expert slots in 30.7 GiB VRAM via `COLI_VK_DEV2=auto`).
   - Combined VRAM expert tier: **5,363 active experts in VRAM** (~113 GB VRAM total).

---

## Measured Inference Performance (GLM-5.3 744B Dual-GPU)

Empirically measured via streaming completions (`stream: true`):

| Metric | Short Prompt (10 tok) | Medium Prompt (50 tok) | Code Prompt (100 tok) |
|---|---|---|---|
| **Time To First Token (TTFT)** | **12.17 s** | **14.66 s** | **15.12 s** |
| **Pure Generation Speed** | N/A (1 token) | **0.52 tok/s** (~1.92 s/tok) | **0.55 tok/s** (~1.81 s/tok) |
| **GPU 0 Active Workload** | Routed experts | 10,886 experts | 12,036 experts |
| **GPU 1 (RTX 5090) Workload** | Routed experts | 4,220 experts (1,610 batches) | 8,807 experts (3,081 batches) |
| **Direct NVMe SSD Streaming** | ~3,200 loads | 12,956 expert loads | 23,257 expert loads |
| **Total Response Latency** | 16.51 s | 70.77 s (30 tokens) | 67.55 s (30 tokens) |

