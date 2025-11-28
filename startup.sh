#!/bin/bash
# Avatar API - Container Startup Script
# Verifies models exist in persistent storage (does NOT download)
#
# IMPORTANT: Run init_storage.sh ONCE before deploying workers
# See docs/DEPLOYMENT.md for setup instructions

set -e  # Exit on error

echo "=========================================="
echo "Avatar API - Container Starting"
echo "=========================================="
echo ""

# Print environment info
echo "Environment:"
echo "  Python version: $(python --version)"
echo "  CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'ERROR: PyTorch not found')"
echo "  Storage path: ${MODEL_STORAGE_PATH:-/runpod-volume/models}"
echo ""

# Verify models exist (does NOT download)
echo "Verifying model availability..."
python /app/core/models.py

if [ $? -ne 0 ]; then
    echo ""
    echo "=========================================="
    echo "✗ STARTUP FAILED - MODELS NOT FOUND"
    echo "=========================================="
    echo ""
    echo "Storage has not been initialized."
    echo ""
    echo "To fix this:"
    echo "  1. SSH into a RunPod pod with the persistent volume mounted"
    echo "  2. Set HF_TOKEN environment variable"
    echo "  3. Set MODEL_STORAGE_PATH to match your pod's mount point"
    echo "     (Pods: /workspace/models, Serverless: /runpod-volume/models)"
    echo "  4. Run: bash /app/init_storage.sh"
    echo ""
    echo "See docs/DEPLOYMENT.md for detailed instructions."
    echo ""
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ Container Ready"
echo "=========================================="
echo ""
echo "Models verified at: ${MODEL_STORAGE_PATH:-/runpod-volume/models}"
echo ""
echo "To test InfiniteTalk generation manually:"
echo "  cd /app/InfiniteTalk"
echo "  python generate_infinitetalk.py --help"
echo ""

# Keep container running for manual testing
# In production, this would be replaced with API server startup
exec tail -f /dev/null
