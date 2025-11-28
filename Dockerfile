# Avatar API - Multi-stage Docker Build for RunPod Serverless
# Stage 1: Build flash-attn and install all Python dependencies
# Stage 2: Download 236GB of models from HuggingFace (EMBEDDED in image)
# Stage 3: Lightweight runtime image with compiled packages + models
#
# IMPORTANT: This creates a ~241GB Docker image (RunPod best practice for production)
# Build requires: ~500GB disk space, HF_TOKEN, 3-5 hours, Docker Hub Pro account

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
# STAGE 2: Model Downloader - Download 236GB models from HuggingFace
# ==============================================================================
FROM builder AS model-downloader

# Accept HuggingFace token as build argument
ARG HF_TOKEN
ENV HF_TOKEN=${HF_TOKEN}

# Verify HF_TOKEN is provided
RUN if [ -z "$HF_TOKEN" ]; then \
        echo "ERROR: HF_TOKEN build argument is required!"; \
        echo "Build with: docker build --build-arg HF_TOKEN=your_token_here ..."; \
        exit 1; \
    fi

# Create models directory
WORKDIR /models

# Download all 3 models using Python + huggingface_hub
RUN python3 << 'PYEOF'
import os
import sys
import time
from pathlib import Path
from huggingface_hub import snapshot_download

models_dir = Path("/models")
hf_token = os.getenv("HF_TOKEN")

# Model configurations (same as init_storage.sh but with corrected sizes)
models = [
    {
        "repo_id": "Wan-AI/Wan2.1-I2V-14B-480P",
        "local_dir": "Wan2.1-I2V-14B-480P",
        "size_gb": 77,
        "description": "Wan 2.1 I2V 14B model"
    },
    {
        "repo_id": "TencentGameMate/chinese-wav2vec2-base",
        "local_dir": "chinese-wav2vec2-base",
        "size_gb": 1.5,
        "description": "Chinese Wav2Vec2 audio encoder"
    },
    {
        "repo_id": "MeiGen-AI/InfiniteTalk",
        "local_dir": "InfiniteTalk",
        "size_gb": 158,
        "description": "InfiniteTalk weights (all variants)"
    }
]

print("="*70)
print("DOWNLOADING MODELS TO DOCKER IMAGE")
print("="*70)
print(f"Total size: ~{sum(m['size_gb'] for m in models)}GB")
print(f"Destination: {models_dir}")
print(f"This will take 1-3 hours depending on network speed...")
print("="*70)
print()

total_start = time.time()

for idx, model in enumerate(models, 1):
    local_path = models_dir / model["local_dir"]

    print(f"[{idx}/{len(models)}] {model['description']}")
    print(f"  Repo: {model['repo_id']}")
    print(f"  Size: ~{model['size_gb']}GB")
    print(f"  Path: {local_path}")
    print()

    try:
        start_time = time.time()

        snapshot_download(
            repo_id=model["repo_id"],
            local_dir=str(local_path),
            token=hf_token,
            resume_download=True,
            max_workers=4
        )

        elapsed = time.time() - start_time
        file_count = len(list(local_path.rglob("*")))
        print(f"  ✓ Downloaded in {elapsed:.1f}s ({elapsed/60:.1f} min) - {file_count} files")
        print()

    except Exception as e:
        print(f"  ✗ Download failed: {e}")
        sys.exit(1)

total_elapsed = time.time() - total_start
print("="*70)
print(f"✓ ALL MODELS DOWNLOADED in {total_elapsed/60:.1f} minutes")
print(f"  Total size: {sum(m['size_gb'] for m in models)}GB")
print("="*70)
PYEOF

# Verify all models were downloaded successfully
RUN echo "Verifying downloaded models..." && \
    ls -lh /models/ && \
    test -d /models/Wan2.1-I2V-14B-480P && \
    test -d /models/chinese-wav2vec2-base && \
    test -d /models/InfiniteTalk && \
    echo "✓ All model directories created successfully"

# ==============================================================================
# STAGE 3: Runtime - Lightweight image with pre-compiled dependencies + models
# ==============================================================================
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    MODEL_STORAGE_PATH=/app/models \
    HF_HOME=/app/models/.cache \
    RUNPOD_INIT_TIMEOUT=900

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

# Copy models from model-downloader stage (~236GB)
COPY --from=model-downloader /models /app/models

# Set working directory
WORKDIR /app

# Copy application code
COPY core/ ./core/
COPY InfiniteTalk/ ./InfiniteTalk/
COPY startup.sh ./
COPY init_storage.sh ./

# Make scripts executable
RUN chmod +x startup.sh init_storage.sh

# Verify models directory exists (created by COPY command above)
RUN test -d /app/models && \
    test -d /app/models/Wan2.1-I2V-14B-480P && \
    test -d /app/models/chinese-wav2vec2-base && \
    test -d /app/models/InfiniteTalk && \
    echo "✓ All models embedded in image successfully"

# Expose port for health checks (if needed later)
EXPOSE 8000

# Container startup: Verify models, then run InfiniteTalk
ENTRYPOINT ["./startup.sh"]
