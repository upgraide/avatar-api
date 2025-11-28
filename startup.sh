#!/bin/bash
# Avatar API - Container Startup Script
# Verifies RunPod Model Store has cached models
#
# IMPORTANT: Configure models in RunPod Endpoint settings (Model Store)
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
echo "  RunPod Model Store path: ${MODEL_STORAGE_PATH:-/runpod-volume}"
echo ""

# Verify RunPod has cached models
echo "Verifying RunPod Model Store cache..."
python /app/core/models.py

if [ $? -ne 0 ]; then
    echo ""
    echo "=========================================="
    echo "✗ STARTUP FAILED - MODELS NOT CACHED"
    echo "=========================================="
    echo ""
    echo "RunPod Model Store has not cached the required models."
    echo ""
    echo "To fix this:"
    echo "  1. Go to RunPod Console → Your Endpoint → Edit Endpoint"
    echo "  2. Scroll to 'Model (optional)' section"
    echo "  3. Add these HuggingFace model URLs:"
    echo "     - https://huggingface.co/Wan-AI/Wan2.1-I2V-14B-480P"
    echo "     - https://huggingface.co/TencentGameMate/chinese-wav2vec2-base"
    echo "     - https://huggingface.co/MeiGen-AI/InfiniteTalk"
    echo "  4. Save and redeploy endpoint"
    echo "  5. RunPod will automatically cache models on workers"
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
echo "Models cached by RunPod Model Store"
echo ""
echo "To test InfiniteTalk generation manually:"
echo "  cd /app/InfiniteTalk"
echo "  python generate_infinitetalk.py \\"
echo "    --ckpt_dir /runpod-volume/Wan-AI/Wan2.1-I2V-14B-480P \\"
echo "    --infinitetalk_dir /runpod-volume/MeiGen-AI/InfiniteTalk/single/infinitetalk.safetensors \\"
echo "    --wav2vec_dir /runpod-volume/TencentGameMate/chinese-wav2vec2-base \\"
echo "    --input_json examples/single_example_image.json \\"
echo "    --save_file /tmp/test_output"
echo ""

# Keep container running for manual testing
# In production, this would be replaced with API server startup
exec tail -f /dev/null
