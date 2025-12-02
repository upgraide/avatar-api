#!/bin/bash
# Avatar API - Pod Startup Script
# Verifies models in /workspace/models and starts FastAPI server
#
# For RunPod Pods:
# - Models should be pre-downloaded to /workspace/models/
# - Pod provides local NVMe storage (mmap works!)
# - API accessible via RunPod proxy: https://{POD_ID}-8000.proxy.runpod.net

set -e  # Exit on error

echo "=========================================="
echo "Avatar API - Pod Starting"
echo "=========================================="
echo ""

# Configuration
MODEL_PATH="${MODEL_STORAGE_PATH:-/workspace/models}"
API_PORT="${API_PORT:-8000}"

echo "Configuration:"
echo "  Model storage: $MODEL_PATH"
echo "  API port: $API_PORT"
echo "  API key: ${API_KEY:+[configured]}"
echo ""

# Print environment info
echo "Environment:"
echo "  Python version: $(python --version 2>&1)"
echo "  CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'checking...')"
if python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null | grep -q True; then
    echo "  GPU: $(python -c 'import torch; print(torch.cuda.get_device_name(0))' 2>/dev/null)"
    echo "  VRAM: $(python -c 'import torch; print(f\"{torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB\")' 2>/dev/null)"
fi
echo ""

# Check if models exist
echo "Checking models in $MODEL_PATH..."
echo ""

MISSING_MODELS=0

check_model() {
    local path="$1"
    local name="$2"

    if [ -d "$path" ]; then
        local size=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "  [OK] $name ($size)"
    else
        echo "  [MISSING] $name"
        echo "           Expected: $path"
        MISSING_MODELS=1
    fi
}

check_model "$MODEL_PATH/Wan2.1-I2V-14B-480P" "Wan2.1-I2V-14B-480P"
check_model "$MODEL_PATH/chinese-wav2vec2-base" "chinese-wav2vec2-base"
check_model "$MODEL_PATH/InfiniteTalk" "InfiniteTalk"

echo ""

if [ $MISSING_MODELS -eq 1 ]; then
    echo "=========================================="
    echo "WARNING: Some models are missing!"
    echo "=========================================="
    echo ""
    echo "To download models, run in the Pod terminal:"
    echo ""
    echo "  # Install huggingface-cli if needed"
    echo "  pip install huggingface-hub"
    echo ""
    echo "  # Download models (~236GB total, takes ~30 min)"
    echo "  huggingface-cli download Wan-AI/Wan2.1-I2V-14B-480P --local-dir $MODEL_PATH/Wan2.1-I2V-14B-480P"
    echo "  huggingface-cli download TencentGameMate/chinese-wav2vec2-base --local-dir $MODEL_PATH/chinese-wav2vec2-base"
    echo "  huggingface-cli download MeiGen-AI/InfiniteTalk --local-dir $MODEL_PATH/InfiniteTalk"
    echo ""
    echo "API will start but /generate will return 503 until models are available."
    echo ""
fi

# Create output directory
mkdir -p /tmp/avatar-outputs

echo "=========================================="
echo "Starting Avatar API Server"
echo "=========================================="
echo ""
echo "API will be available at:"
echo "  Local: http://0.0.0.0:$API_PORT"
echo "  RunPod Proxy: https://{POD_ID}-$API_PORT.proxy.runpod.net"
echo ""
echo "Endpoints:"
echo "  GET  /health   - Health check"
echo "  POST /generate - Generate video"
echo "  GET  /docs     - API documentation"
echo ""

# Start FastAPI server
exec python -m uvicorn api:app --host 0.0.0.0 --port $API_PORT
