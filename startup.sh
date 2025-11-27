#!/bin/bash
# Avatar API - Container Startup Script
# Checks for models in persistent storage and downloads if missing

set -e  # Exit on error

echo "=========================================="
echo "Avatar API - Container Starting"
echo "=========================================="
echo ""

# Print environment info
echo "Environment:"
echo "  Python version: $(python --version)"
echo "  CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'PyTorch not installed yet')"
echo "  Storage path: ${MODEL_STORAGE_PATH:-/runpod-volume/models}"
echo ""

# Install PyTorch with CUDA 12.1 support
echo "Installing PyTorch with CUDA 12.1..."
pip install torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1 --index-url https://download.pytorch.org/whl/cu121 --no-cache-dir
echo "✓ PyTorch installed"
echo ""

# Run model download check
echo "Checking model availability..."
python /app/core/models.py

if [ $? -ne 0 ]; then
    echo "✗ Model download failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "Container Ready"
echo "=========================================="
echo ""
echo "Models are available at: ${MODEL_STORAGE_PATH:-/runpod-volume/models}"
echo ""
echo "To test InfiniteTalk generation manually:"
echo "  cd /app/InfiniteTalk"
echo "  python generate_infinitetalk.py --help"
echo ""

# Keep container running for manual testing
# In production, this would be replaced with API server startup
exec tail -f /dev/null
