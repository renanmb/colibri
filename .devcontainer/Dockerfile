# syntax=docker/dockerfile:1.4
ARG BASE_IMAGE=mcr.microsoft.com/playwright:v1.58.2-jammy
FROM ${BASE_IMAGE}

LABEL maintainer="boredengineering"
LABEL description="Colibri C Inference Engine, Vulkan & Terminal Agent Container"

# Copy fast Rust-based Python package manager (uv)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Environment Variables
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    PYTHONUNBUFFERED=1

# Layer 1: Core Toolchain, Vulkan SDK, OpenMP & Direct I/O
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    git-lfs \
    curl \
    wget \
    unzip \
    rsync \
    jq \
    tmux \
    htop \
    nano \
    sudo \
    python3-pip \
    python3-dev \
    libvulkan1 \
    libvulkan-dev \
    vulkan-tools \
    mesa-vulkan-drivers \
    glslang-tools \
    spirv-tools \
    libomp-dev \
    libaio-dev \
    fio \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Agent CLIs & Model Context Protocol (MCP) Tools
RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @modelcontextprotocol/server-filesystem && \
    (curl -fsSL https://chatgpt.com/codex/install.sh | bash || true) && \
    (ln -sf /root/.local/bin/codex /usr/local/bin/codex 2>/dev/null || true) && \
    (curl -fsSL https://antigravity.google/cli/install.sh | bash || true) && \
    (ln -sf /root/.local/bin/agy /usr/local/bin/agy 2>/dev/null || true) && \
    (curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser || true)

# Layer 3: Python Essentials for Model Conversion and HF CLI
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel && \
    pip3 install --no-cache-dir \
        "huggingface_hub[cli]" \
        numpy \
        tqdm \
        click \
        requests

# Layer 4: Dedicated Model Mount & Vulkan ICD Environment
RUN mkdir -p /models /workspaces && \
    chmod -R 777 /models /workspaces && \
    mkdir -p /etc/vulkan/icd.d && \
    echo '{"file_format_version": "1.0.0", "ICD": {"library_path": "libGLX_nvidia.so.0", "api_version": "1.3"}}' > /etc/vulkan/icd.d/nvidia_icd.json

WORKDIR /workspaces

CMD ["bash"]
