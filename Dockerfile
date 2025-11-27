# Avatar API - Lightweight Docker Container for RunPod Serverless
# Base: NVIDIA CUDA 12.1 + cuDNN 8 for GPU acceleration
# Models: Downloaded at runtime to persistent storage (not baked in)

FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    MODEL_STORAGE_PATH=/runpod-volume/models \
    HF_HOME=/runpod-volume/models/.cache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    python3.10-venv \
    ffmpeg \
    git \
    wget \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Set working directory
WORKDIR /app

# Copy requirements first for Docker layer caching
COPY requirements.txt ./

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY core/ ./core/
COPY InfiniteTalk/ ./InfiniteTalk/
COPY startup.sh ./

# Make startup script executable
RUN chmod +x startup.sh

# Create directories for persistent storage mount point
RUN mkdir -p /runpod-volume/models

# Expose port for health checks (if needed later)
EXPOSE 8000

# Container startup: Check/download models, then run InfiniteTalk
ENTRYPOINT ["./startup.sh"]
