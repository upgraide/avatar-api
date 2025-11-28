#!/bin/bash
# Avatar API - Container Startup Script
# Verifies models embedded in Docker image are accessible
#
# IMPORTANT: Models are embedded in Docker image at /app/models/ during build
# See docs/DEPLOYMENT.md for build and deployment instructions

set -e  # Exit on error

echo "=========================================="
echo "Avatar API - Container Starting"
echo "=========================================="
echo ""
echo "IMPORTANT: Cold start may take 10-15 minutes for model loading into GPU"
echo "RUNPOD_INIT_TIMEOUT is set to ${RUNPOD_INIT_TIMEOUT:-900}s to prevent health check timeout"
echo ""

# Print environment info
echo "Environment:"
echo "  Python version: $(python --version)"
echo "  CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'ERROR: PyTorch not found')"
echo "  Model storage path: ${MODEL_STORAGE_PATH:-/app/models}"
echo "  Init timeout: ${RUNPOD_INIT_TIMEOUT:-900}s"
echo ""

# Verify embedded models are accessible
echo "Verifying embedded models..."
python /app/core/models.py

if [ $? -ne 0 ]; then
    echo ""
    echo "=========================================="
    echo "✗ STARTUP FAILED - MODELS NOT FOUND"
    echo "=========================================="
    echo ""
    echo "Required models were not found in Docker image."
    echo "This indicates the image was not built correctly."
    echo ""
    echo "Models should be embedded during Docker build:"
    echo "  docker build --build-arg HF_TOKEN=your_token_here -t avatar-api:v1.0 ."
    echo ""
    echo "Expected model locations:"
    echo "  /app/models/Wan2.1-I2V-14B-480P/"
    echo "  /app/models/chinese-wav2vec2-base/"
    echo "  /app/models/InfiniteTalk/"
    echo ""
    echo "See docs/DEPLOYMENT.md for detailed build instructions."
    echo ""
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ Container Ready"
echo "=========================================="
echo ""
echo "Models embedded in Docker image and accessible"
echo "Total model size: ~236GB (embedded in image)"
echo ""
echo "To test InfiniteTalk generation manually:"
echo "  cd /app/InfiniteTalk"
echo "  python generate_infinitetalk.py \\"
echo "    --task infinitetalk-14B \\"
echo "    --size infinitetalk-720 \\"
echo "    --ckpt_dir /app/models/Wan2.1-I2V-14B-480P \\"
echo "    --infinitetalk_dir /app/models/InfiniteTalk \\"
echo "    --wav2vec_dir /app/models/chinese-wav2vec2-base \\"
echo "    --input_json examples/single_example_image.json \\"
echo "    --save_file /tmp/test_output"
echo ""

# Keep container running for manual testing
# In production, this would be replaced with API server startup
exec tail -f /dev/null
