---
name: colibri-glm
description: >-
  Procedures, runbooks, and command sequences for compiling, downloading,
  configuring, and serving GLM-5.3 and GLM-5.3-Flash models locally on the
  Colibrì C engine with Vulkan GPU tiering and dual-NVMe disk storage.
---

# Colibrì GLM Execution Skill

This skill provides step-by-step procedures for managing GLM models on this workstation using the Colibrì pure-C engine.

## 1. Engine Compilation

Compile with native CPU vectorization (AVX-512) and Vulkan acceleration:

```bash
# For GLM-5.3 (744B flagship model - uses colibri engine)
make -C /workspaces/colibri/c colibri VK=1 ARCH=native

# For GLM-5.3-Flash (321B multimodal model - uses glm53 engine)
make -C /workspaces/colibri/c glm53 VK=1 ARCH=native
```

Verify build:
```bash
/workspaces/colibri/c/colibri 2>&1 | head -n 10
/workspaces/colibri/c/glm53 2>&1 | head -n 10
```

---

## 2. Model Downloads (to Dedicated NVMe at `/models`)

The dedicated second NVMe SSD (Samsung 9100 PRO 4TB) is mounted at `/models` (host path `/mnt/models_fast`). Always target this directory.

### GLM-5.3 (744B Flagship)
```bash
huggingface-cli download Justvugg/GLM-5.3-colibri-int4-g64 \
    --local-dir /models/glm-5.3 \
    --local-dir-use-symlinks False
```

### GLM-5.3-Flash (321B Multimodal)
```bash
huggingface-cli download Justvugg/GLM-5.3-Flash-colibri-int4-g64 \
    --local-dir /models/glm-5.3-flash \
    --local-dir-use-symlinks False
```

---

## 3. Model Verification & Health Checks

1. Verify model configuration and shard files:
   ```bash
   python3 /workspaces/colibri/c/coli doctor --model /models/glm-5.3
   ```
2. Benchmark disk streaming throughput:
   ```bash
   /workspaces/colibri/c/iobench /models/<shard-file> 19 64 8 1
   ```

---

## 4. Serving & Inference Workflows

Always set `COLI_VULKAN=1` and ensure `DISPLAY=` is headless if running without X11:

### Interactive Terminal Chat:
```bash
export COLI_VULKAN=1
export DISPLAY=
python3 /workspaces/colibri/c/coli chat --model /models/glm-5.3
```

### Web UI Dashboard:
```bash
export COLI_VULKAN=1
export DISPLAY=
python3 /workspaces/colibri/c/coli web --model /models/glm-5.3 --host 0.0.0.0 --port 8000
```

### OpenAI / Anthropic API Server:
```bash
export COLI_VULKAN=1
export DISPLAY=
python3 /workspaces/colibri/c/coli serve --model /models/glm-5.3 --host 0.0.0.0 --port 8000
```
