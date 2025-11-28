# Building the Avatar API Docker Image with Embedded Models

This guide explains how to build the Avatar API Docker image with 236GB of models embedded for production deployment on RunPod Serverless.

## Overview

**Architecture:** Embed all 3 HuggingFace models directly in the Docker image (RunPod best practice for production)

**Image Size:** ~241GB (5GB base + 236GB models)

**Build Time:** 3-5 hours (downloading 236GB from HuggingFace)

**Requirements:**
- Docker Hub Pro account ($5/month) - Free tier won't work for 241GB image
- HuggingFace access token
- Build machine with 500GB+ free disk space
- x86_64 architecture (RunPod compatible)

---

## Why Embed Models in Docker Image?

From RunPod's best practices documentation:

> "Embed models in Docker images: Package your ML models directly within your worker container image instead of downloading them in your handler function. This strategy places models on the worker's high-speed local storage (SSD/NVMe), dramatically reducing the time needed to load models into GPU memory. **This approach is optimal for production environments**, though extremely large models (500GB+) may require network volume storage."

**Benefits:**
- ✅ Supports multiple models (RunPod Model Cache only supports 1)
- ✅ mmap support (local NVMe disk, no network storage issues)
- ✅ Fast cold starts (~60s after first worker pulls image)
- ✅ No network volume needed (saves ~$43/month for 500GB)
- ✅ Deterministic deployments (models versioned with image)
- ✅ Production-grade architecture

---

## Prerequisites

### 1. Docker Hub Pro Account

**Why needed:** Docker Hub free tier has 5GB bandwidth limit per 6 hours. Pushing 241GB requires paid plan.

**Setup:**
1. Go to https://hub.docker.com/
2. Upgrade to Docker Hub Pro ($5/month)
3. Create repository: `yourusername/avatar-api`

### 2. HuggingFace Access Token

**Get your token:**
1. Go to https://huggingface.co/settings/tokens
2. Create a new token with `read` permissions
3. Save it securely (needed for Docker build)

### 3. Build Machine

**Option A: Cloud VM (Recommended)**

Use Hetzner, AWS, or any cloud provider with:
- 500GB+ disk space
- x86_64 architecture
- Good network connection (3+ hours to download 236GB)

Example (Hetzner CX51):
```bash
# 8 vCPU, 32GB RAM, 240GB NVMe + 500GB attached volume
# Cost: ~$0.09/hour = $0.45 for 5-hour build
```

**Option B: GitHub Actions**

Use GitHub Actions with self-hosted runner:
- Requires 500GB+ disk on runner machine
- Can take 5-8 hours (slower network)
- Free if using own runner hardware

**Option C: Local Machine (if x86_64 + 500GB disk)**

Only if you have:
- x86_64 architecture (not ARM Mac)
- 500GB+ free disk space
- Fast internet connection
- Time to run 3-5 hour build

---

## Build Instructions

### Step 1: Prepare Build Environment

```bash
# On your build machine (cloud VM or local)
git clone https://github.com/yourusername/avatar-api.git
cd avatar-api

# Check disk space (need 500GB+ free)
df -h .

# Login to Docker Hub
docker login
# Enter Docker Hub Pro username + password
```

### Step 2: Build the Docker Image

```bash
# Set your HuggingFace token
export HF_TOKEN="your_huggingface_token_here"

# Build the image (will take 3-5 hours)
docker build \
  --build-arg HF_TOKEN=$HF_TOKEN \
  --platform linux/amd64 \
  -t yourusername/avatar-api:v1.0 \
  -t yourusername/avatar-api:latest \
  .
```

**Build stages:**
1. Stage 1: Compile Python dependencies (~15 min)
2. Stage 2: Download 236GB models from HuggingFace (~2-4 hours)
3. Stage 3: Copy models + code into runtime image (~30 min)

**Expected output:**
```
DOWNLOADING MODELS TO DOCKER IMAGE
======================================================================
Total size: ~236.5GB
Destination: /models
This will take 1-3 hours depending on network speed...
======================================================================

[1/3] Wan 2.1 I2V 14B model
  Repo: Wan-AI/Wan2.1-I2V-14B-480P
  Size: ~77GB
  Path: /models/Wan2.1-I2V-14B-480P

  ✓ Downloaded in 3245.2s (54.1 min) - 127 files

[2/3] Chinese Wav2Vec2 audio encoder
  Repo: TencentGameMate/chinese-wav2vec2-base
  Size: ~1.5GB
  Path: /models/chinese-wav2vec2-base

  ✓ Downloaded in 89.3s (1.5 min) - 18 files

[3/3] InfiniteTalk weights (all variants)
  Repo: MeiGen-AI/InfiniteTalk
  Size: ~158GB
  Path: /models/InfiniteTalk

  ✓ Downloaded in 5123.7s (85.4 min) - 342 files

======================================================================
✓ ALL MODELS DOWNLOADED in 141.0 minutes
  Total size: 236.5GB
======================================================================
```

### Step 3: Verify the Build

```bash
# Check image size
docker images yourusername/avatar-api:v1.0
# Should show ~241GB

# Test the image locally (requires GPU)
docker run --rm --gpus all yourusername/avatar-api:v1.0
# Should print "✅ Container Ready" after verifying embedded models
```

### Step 4: Push to Docker Hub

**Warning:** This will upload 241GB and may take 2-6 hours depending on your upload speed.

```bash
# Push the image (this will take 2-6 hours)
docker push yourusername/avatar-api:v1.0
docker push yourusername/avatar-api:latest
```

**Expected time:**
- 100 Mbps upload: ~5.5 hours
- 500 Mbps upload: ~1.1 hours
- 1 Gbps upload: ~35 minutes

**Monitor progress:**
```bash
# Push shows progress for each layer
# The largest layer (models) will be ~236GB
```

---

## Troubleshooting

### Build Error: "HF_TOKEN build argument is required"

**Cause:** Missing HuggingFace token

**Solution:**
```bash
export HF_TOKEN="your_token_here"
docker build --build-arg HF_TOKEN=$HF_TOKEN ...
```

### Build Error: "No space left on device"

**Cause:** Insufficient disk space

**Solution:**
```bash
# Check disk space
df -h .

# Clean up Docker build cache
docker system prune -a

# Or use larger VM/volume
```

### Build Error: "Repository not found" (HuggingFace)

**Cause:** Invalid HF_TOKEN or model is gated

**Solution:**
1. Verify token: https://huggingface.co/settings/tokens
2. Check if models require approval:
   - https://huggingface.co/Wan-AI/Wan2.1-I2V-14B-480P
   - https://huggingface.co/MeiGen-AI/InfiniteTalk
   - https://huggingface.co/TencentGameMate/chinese-wav2vec2-base
3. Accept terms if gated model

### Push Error: "Denied: requested access to the resource is denied"

**Cause:** Not logged into Docker Hub or insufficient permissions

**Solution:**
```bash
# Login to Docker Hub
docker login

# Ensure repository exists at hub.docker.com/r/yourusername/avatar-api
# Ensure you have Docker Hub Pro (free tier won't work for 241GB)
```

### ARM Mac Build Error

**Cause:** ARM architecture not compatible with RunPod x86_64

**Solution:** Use cloud VM or GitHub Actions with x86_64 architecture

---

## Next Steps

After successfully pushing the image:

1. **Deploy to RunPod:**
   - Follow `docs/DEPLOYMENT.md` for RunPod Serverless configuration
   - Point endpoint to `yourusername/avatar-api:v1.0`
   - **Important:** Do NOT configure RunPod Model Cache (models already embedded)
   - Set `RUNPOD_INIT_TIMEOUT=900` for 15-minute cold start timeout

2. **Test AC #4:**
   - SSH into RunPod worker
   - Run manual InfiniteTalk generation (see `startup.sh` output)
   - Verify 720p video generation works
   - Measure generation time (expect 30-120s)

3. **Monitor Performance:**
   - First worker start: 10-20 min (downloads 241GB image)
   - Subsequent workers: <60s (RunPod caches image on hosts)
   - Cold start (model load to GPU): ~10-15 min (RUNPOD_INIT_TIMEOUT handles this)

---

## Cost Breakdown

### One-Time Costs
- **Docker Hub Pro:** $5/month (required for 241GB image)
- **Build VM:** ~$0.50 (5 hours on Hetzner CX51)
- **HuggingFace:** Free (token + downloads)

### Ongoing Costs
- **RunPod Serverless:** $0.00019/second when running (L40S GPU)
- **No storage costs** (models in image, no network volume needed)
- **Image hosting:** Included in Docker Hub Pro

### Total Monthly Cost (assuming 100 hours/month GPU usage)
- Docker Hub Pro: $5/month
- RunPod GPU: $68.40/month (100 hours × $0.684/hour)
- **Total: ~$73/month**

Compare to network volume approach:
- Network volume: $43/month (500GB persistent storage)
- RunPod GPU: $68.40/month
- **Total: ~$111/month** + mmap issues + slower cold starts

**Savings: $38/month + better performance**

---

## Architecture Notes

### Model Paths in Container

```
/app/
├── models/                          # 236GB embedded models
│   ├── Wan2.1-I2V-14B-480P/        # 77GB
│   ├── chinese-wav2vec2-base/      # 1.5GB
│   └── InfiniteTalk/               # 158GB
├── core/
│   └── models.py                    # Model verification
├── InfiniteTalk/                    # Source code
└── startup.sh                       # Entrypoint
```

### Environment Variables

Set in Dockerfile (already configured):
- `MODEL_STORAGE_PATH=/app/models`
- `HF_HOME=/app/models/.cache`
- `RUNPOD_INIT_TIMEOUT=900` (15 min for cold start)

### InfiniteTalk Command (Manual Testing)

```bash
cd /app/InfiniteTalk
python generate_infinitetalk.py \
  --task infinitetalk-14B \
  --size infinitetalk-720 \
  --ckpt_dir /app/models/Wan2.1-I2V-14B-480P \
  --infinitetalk_dir /app/models/InfiniteTalk \
  --wav2vec_dir /app/models/chinese-wav2vec2-base \
  --input_json examples/single_example_image.json \
  --save_file /tmp/test_output
```

---

## References

- **RunPod Best Practices:** https://docs.runpod.io/serverless/endpoints/endpoint-configurations#reducing-worker-startup-times
- **Docker Multi-Stage Builds:** https://docs.docker.com/build/building/multi-stage/
- **HuggingFace Hub:** https://huggingface.co/docs/huggingface_hub/guides/download
- **Story 1.1:** `docs/sprint_artifacts/story-serverless-avatar-api-1.md`
