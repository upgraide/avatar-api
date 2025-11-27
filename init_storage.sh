#!/bin/bash
# Avatar API - Storage Initialization Script
#
# PURPOSE: One-time setup to download models to RunPod persistent storage
# RUN THIS ONCE before deploying serverless workers
#
# Usage:
#   1. SSH into a RunPod pod with persistent volume mounted
#   2. Set HF_TOKEN environment variable
#   3. Run: bash init_storage.sh
#
# This script is IDEMPOTENT - safe to run multiple times.
# It will skip models that are already downloaded.

set -e

echo "=========================================="
echo "Avatar API - Storage Initialization"
echo "=========================================="
echo ""

# Check environment
STORAGE_PATH="${MODEL_STORAGE_PATH:-/workspace/models}"

if [ ! -d "$STORAGE_PATH" ]; then
    echo "✗ ERROR: Storage path not found: $STORAGE_PATH"
    echo ""
    echo "Make sure RunPod persistent volume is mounted at /workspace"
    echo "and that $STORAGE_PATH directory exists (mkdir -p $STORAGE_PATH)"
    exit 1
fi

if [ -z "$HF_TOKEN" ]; then
    echo "✗ ERROR: HF_TOKEN environment variable not set"
    echo ""
    echo "Get your token from: https://huggingface.co/settings/tokens"
    echo "Then run: export HF_TOKEN='your_token_here'"
    exit 1
fi

echo "Configuration:"
echo "  Storage path: $STORAGE_PATH"
echo "  HF_TOKEN: ${HF_TOKEN:0:8}... (hidden)"
echo ""

# Install PyTorch if not already installed (needed for huggingface_hub)
if ! python -c "import torch" 2>/dev/null; then
    echo "Installing PyTorch with CUDA 12.1..."
    pip install torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1 --index-url https://download.pytorch.org/whl/cu121 --no-cache-dir
    echo "✓ PyTorch installed"
    echo ""
fi

# Ensure huggingface_hub is installed
if ! python -c "import huggingface_hub" 2>/dev/null; then
    echo "Installing huggingface_hub..."
    pip install huggingface_hub --no-cache-dir
    echo "✓ huggingface_hub installed"
    echo ""
fi

# Download models using Python
echo "Starting model downloads..."
echo "This will take 10-15 minutes on first run."
echo ""

python3 << 'PYEOF'
import os
import sys
import time
from pathlib import Path
from huggingface_hub import snapshot_download

storage_path = Path(os.getenv("MODEL_STORAGE_PATH", "/runpod-volume/models"))
hf_token = os.getenv("HF_TOKEN")

# Model configurations
models = [
    {
        "repo_id": "Wan-AI/Wan2.1-I2V-14B-480P",
        "local_dir": "Wan2.1-I2V-14B-480P",
        "size_gb": 40,
        "description": "Wan 2.1 Image-to-Video 14B model"
    },
    {
        "repo_id": "TencentGameMate/chinese-wav2vec2-base",
        "local_dir": "chinese-wav2vec2-base",
        "size_gb": 1,
        "description": "Chinese Wav2Vec2 audio encoder"
    },
    {
        "repo_id": "MeiGen-AI/InfiniteTalk",
        "local_dir": "InfiniteTalk",
        "size_gb": 2,
        "description": "InfiniteTalk weights and audio conditioning"
    }
]

print(f"Downloading {len(models)} models to {storage_path}")
print("")

total_start = time.time()
downloaded = 0
skipped = 0

for model in models:
    local_path = storage_path / model["local_dir"]

    print(f"{'='*60}")
    print(f"Model: {model['description']}")
    print(f"  Repo: {model['repo_id']}")
    print(f"  Size: ~{model['size_gb']}GB")
    print(f"  Destination: {local_path}")
    print("")

    # Check if already downloaded (has files, not just empty dir)
    if local_path.exists() and any(local_path.iterdir()):
        file_count = len(list(local_path.iterdir()))
        print(f"✓ Already exists ({file_count} files) - skipping")
        print("")
        skipped += 1
        continue

    # Download model
    try:
        start_time = time.time()
        print("  Downloading... (this may take several minutes)")

        snapshot_download(
            repo_id=model["repo_id"],
            local_dir=str(local_path),
            token=hf_token,
            resume_download=True,
            max_workers=4
        )

        elapsed = time.time() - start_time
        print(f"✓ Downloaded in {elapsed:.1f}s ({elapsed/60:.1f} min)")
        print("")
        downloaded += 1

    except Exception as e:
        print(f"✗ Download failed: {e}")
        sys.exit(1)

total_elapsed = time.time() - total_start

print(f"{'='*60}")
print("Summary:")
print(f"  Downloaded: {downloaded} models")
print(f"  Skipped: {skipped} models (already present)")
print(f"  Total time: {total_elapsed:.1f}s ({total_elapsed/60:.1f} min)")
print("")

PYEOF

if [ $? -ne 0 ]; then
    echo ""
    echo "✗ Model download failed!"
    exit 1
fi

# Create ready marker file
READY_MARKER="$STORAGE_PATH/.storage_ready"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$READY_MARKER"

echo "=========================================="
echo "✅ Storage Initialization Complete"
echo "=========================================="
echo ""
echo "Models are ready at: $STORAGE_PATH"
echo "Ready marker created: $READY_MARKER"
echo ""
echo "Next steps:"
echo "  1. Deploy your RunPod serverless endpoint"
echo "  2. Workers will start in <60s (no downloads needed)"
echo ""
