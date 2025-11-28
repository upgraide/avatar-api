# Avatar API - Multi-stage Docker Build for RunPod Serverless
# Stage 1: Build flash-attn and install all Python dependencies
# Stage 2: Lightweight runtime image with compiled packages
# Models: Downloaded at runtime to persistent storage (not baked in)

# ==============================================================================
# STAGE 1: Builder - Compile flash-attn and install all dependencies
# ==============================================================================
FROM nvidia/cuda:12.1.0-cudnn8-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Install Python and build tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    python3.10-venv \
    git \
    wget \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

WORKDIR /build

# Copy requirements
COPY requirements.txt ./

# Install Python dependencies per official InfiniteTalk docs
# 1. Upgrade pip
RUN pip install --no-cache-dir --upgrade pip

# 2. PyTorch 2.5.1 with CUDA 12.1 (REQUIRED: xfuser needs torch.distributed.tensor.experimental)
RUN pip install --no-cache-dir torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu121

# 3. xformers 0.0.29.post1 with CUDA 12.1 (compatible with PyTorch 2.5.1)
RUN pip install --no-cache-dir xformers==0.0.29.post1 --index-url https://download.pytorch.org/whl/cu121

# 4. Build dependencies for flash-attn
RUN pip install --no-cache-dir ninja psutil packaging wheel

# 5. flash-attn (compile from source, requires torch + build deps)
RUN pip install --no-cache-dir --no-build-isolation flash_attn==2.7.4.post1

# 6. InfiniteTalk dependencies (includes misaki, soundfile, librosa, etc.)
RUN pip install --no-cache-dir -r requirements.txt

# ==============================================================================
# STAGE 2: Runtime - Lightweight image with pre-compiled dependencies
# ==============================================================================
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    MODEL_STORAGE_PATH=/runpod-volume/models \
    HF_HOME=/runpod-volume/models/.cache

# Install runtime system dependencies (Python + FFmpeg)
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Copy Python packages from builder stage
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Set working directory
WORKDIR /app

# Copy application code
COPY core/ ./core/
COPY InfiniteTalk/ ./InfiniteTalk/
COPY startup.sh ./
COPY init_storage.sh ./

# Make scripts executable
RUN chmod +x startup.sh init_storage.sh

# Create directories for persistent storage mount point
RUN mkdir -p /runpod-volume/models

# Expose port for health checks (if needed later)
EXPOSE 8000

# Container startup: Verify models, then run InfiniteTalk
ENTRYPOINT ["./startup.sh"]
