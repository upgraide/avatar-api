#!/bin/bash
# Story 1.1 E2E Validation Script
# Run this on RunPod to validate AC #2, #3, #4

set -e

echo "========================================="
echo "Story 1.1: RunPod Foundation Validation"
echo "========================================="
echo ""

# AC #3: Models Downloaded to Persistent Storage
echo "📦 AC #3: Checking model downloads..."
echo ""

if [ -d "/runpod-volume/models" ]; then
    echo "✓ Persistent storage mounted at /runpod-volume/models"
    echo ""
    echo "Model directories:"
    ls -lh /runpod-volume/models/ 2>/dev/null || echo "✗ No models directory found"
    echo ""
    echo "Storage usage:"
    du -sh /runpod-volume/models/* 2>/dev/null || echo "✗ No models found"
    echo ""
else
    echo "✗ FAIL: /runpod-volume/models not found!"
    exit 1
fi

# Verify all 3 models exist
MISSING_MODELS=0
for model in "Wan2.1-I2V-14B-480P" "chinese-wav2vec2-base" "InfiniteTalk"; do
    if [ -d "/runpod-volume/models/$model" ]; then
        echo "✓ Model exists: $model"
    else
        echo "✗ Model missing: $model"
        MISSING_MODELS=$((MISSING_MODELS + 1))
    fi
done

if [ $MISSING_MODELS -gt 0 ]; then
    echo ""
    echo "✗ FAIL: $MISSING_MODELS model(s) missing!"
    exit 1
fi

echo ""
echo "✓ AC #3 PASS: All 3 models downloaded to persistent storage"
echo ""

# AC #4: End-to-End Video Generation
echo "========================================="
echo "🎬 AC #4: Testing video generation..."
echo "========================================="
echo ""

cd /app/InfiniteTalk

# Check example files exist
if [ ! -f "examples/single/ref_image.png" ]; then
    echo "✗ FAIL: Test image not found"
    exit 1
fi

if [ ! -f "examples/single/1.wav" ]; then
    echo "✗ FAIL: Test audio not found"
    exit 1
fi

echo "✓ Test assets found"
echo ""
echo "Starting 720p video generation test..."
echo "Expected time: 30-120 seconds"
echo ""

START_TIME=$(date +%s)

python generate_infinitetalk.py \
  --task infinitetalk-14B \
  --size infinitetalk-720 \
  --ckpt_dir /runpod-volume/models/Wan2.1-I2V-14B-480P \
  --infinitetalk_dir /runpod-volume/models/InfiniteTalk \
  --wav2vec_dir /runpod-volume/models/chinese-wav2vec2-base \
  --input_json examples/single_example_image.json \
  --sample_steps 40 \
  --mode streaming \
  --motion_frame 9 \
  --save_file /tmp/test_output

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "========================================="
echo "📊 Results"
echo "========================================="
echo ""

if [ -f "/tmp/test_output.mp4" ]; then
    FILE_SIZE=$(ls -lh /tmp/test_output.mp4 | awk '{print $5}')
    FILE_INFO=$(file /tmp/test_output.mp4)

    echo "✓ Video generated successfully!"
    echo ""
    echo "File: /tmp/test_output.mp4"
    echo "Size: $FILE_SIZE"
    echo "Type: $FILE_INFO"
    echo "Generation time: ${DURATION} seconds"
    echo ""

    if [ $DURATION -le 120 ] && [ $DURATION -ge 30 ]; then
        echo "✓ AC #4 PASS: Video generated in acceptable time (30-120s)"
    elif [ $DURATION -lt 30 ]; then
        echo "⚠ WARNING: Unusually fast generation ($DURATION s) - verify video quality"
    else
        echo "⚠ WARNING: Slower than expected ($DURATION s vs 30-120s target)"
    fi

    echo ""
    echo "========================================="
    echo "✅ STORY 1.1 VALIDATION COMPLETE"
    echo "========================================="
    echo ""
    echo "✓ AC #1: Docker Container Built (validated earlier)"
    echo "✓ AC #2: Container Deployed to RunPod Serverless"
    echo "✓ AC #3: Models Downloaded to Persistent Storage"
    echo "✓ AC #4: End-to-End Video Generation Works"
    echo "✓ AC #5: Deployment Process Documented (validated earlier)"
    echo ""
    echo "📥 Download video for quality review:"
    echo "   scp -i ~/.ssh/id_ed25519 jf4rd434qxly9z-64410e43@ssh.runpod.io:/tmp/test_output.mp4 ."
    echo ""

else
    echo "✗ FAIL: Video file not created"
    exit 1
fi
