# Avatar API - RunPod Deployment Guide

This guide walks you through deploying the Avatar API container to RunPod Serverless with persistent model storage.

## Prerequisites

Before deploying, ensure you have:

1. **RunPod Account**

   - Sign up at [runpod.io](https://www.runpod.io/)
   - Add payment method to account
   - Minimum $10 initial credit recommended

2. **Docker Hub Account** (or other container registry)

   - Sign up at [hub.docker.com](a)
   - Create repository: `yourusername/avatar-api`

3. **Hugging Face Account**

   - Sign up at [huggingface.co](https://huggingface.co/)
   - Generate access token at [Settings → Access Tokens](https://huggingface.co/settings/tokens)
   - Token needs read access for public models

4. **Local Tools**
   - Docker installed (for building container)
   - Git (for cloning repository)

## Step 1: Clone and Build Container

### 1.1 Clone Repository

```bash
git clone <your-repository-url>
cd avatar-api
```

### 1.2 Build Docker Image

**Option A: GitHub Actions (Recommended)**

This method uses GitHub's cloud runners to build the x86 image, avoiding local architecture and resource constraints.

**Setup (One-time):**

1. **Configure Docker Hub secrets in GitHub:**
   - Go to your GitHub repository → Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Add `DOCKER_USERNAME` with your Docker Hub username
   - Add `DOCKER_PASSWORD` with your Docker Hub password or access token

2. **Trigger the build:**
   - Option 1 (Automatic): Push to `main` or `master` branch triggers build automatically
   - Option 2 (Manual): Go to Actions → "Build and Push Docker Image" → Run workflow

**Build takes 10-15 minutes.** Check the Actions tab for progress.

**Option B: Local Build (x86 machines only)**

For ARM Macs or machines with limited RAM, use Option A instead.

```bash
# Build the container (requires x86 architecture and >8GB RAM)
docker build -t avatar-api:v1.0 .

# Verify image size (should be <5GB without models)
docker images | grep avatar-api

# Tag for your Docker Hub account
docker tag avatar-api:v1.0 yourusername/avatar-api:v1.0

# Login to Docker Hub
docker login

# Push image
docker push yourusername/avatar-api:v1.0
```

**Expected image size:** ~4-5GB (base CUDA image + dependencies, models NOT included)

**⏱️ Time required:** 5-10 minutes (depends on internet speed)

## Step 2: Configure RunPod Persistent Storage

RunPod persistent storage keeps models cached between container restarts, avoiding re-downloads.

### 2.1 Create Persistent Volume

1. Navigate to [RunPod Storage](https://www.runpod.io/console/storage)
2. Click **"Create Network Volume"**
3. Configure:
   - **Name:** `avatar-api-models`
   - **Size:** 50 GB (for 43GB models + headroom)
   - **Region:** Choose region closest to you
4. Click **Create**

**💰 Cost:** ~$4.30/month for 43GB storage

### 2.2 Note Volume Details

After creation, note:

- Volume ID (e.g., `vol_xxxxx`)
- Region (must match your serverless endpoint)

## Step 3: Initialize Persistent Storage (One-Time Setup)

**CRITICAL:** This step must be completed ONCE before deploying workers.

Models (~43GB) must be downloaded to persistent storage before worker containers can start. This init step ensures workers start in <60s instead of waiting 10-15 minutes for downloads.

### 3.1 Create Temporary Init Pod

1. Navigate to [RunPod Pods](https://www.runpod.io/console/pods)
2. Click **"+ Deploy"**
3. Select **GPU Pod** (Community Cloud is fine - we just need temporary access)
4. Configure:
   - **GPU Type:** Any (cheapest option - we're just downloading files)
   - **Template:** PyTorch or similar (needs Python + pip)
   - **Disk:** 10GB (minimum)
   - **Volume:** Attach your `avatar-api-models` volume at `/runpod-volume`

5. Click **Deploy** and wait for pod to start

**⏱️ Time required:** 2-3 minutes for pod startup

### 3.2 Get Init Script

You have two options to get the init script:

**Option A: From your local repository (simpler)**

```bash
# Copy script from your local clone to the pod
scp -P <PORT> -i ~/.ssh/id_ed25519 init_storage.sh root@<POD_IP>:/tmp/
```

**Option B: From GitHub repository**

SSH into your pod first:

```bash
# SSH into pod (get connection details from RunPod console)
ssh root@<POD_IP> -p <PORT> -i ~/.ssh/id_ed25519

# Download init script from your repository
wget https://raw.githubusercontent.com/yourusername/avatar-api/main/init_storage.sh -O /tmp/init_storage.sh
chmod +x /tmp/init_storage.sh
```

### 3.3 Run Storage Initialization

SSH into the pod (if not already connected):

```bash
ssh root@<POD_IP> -p <PORT> -i ~/.ssh/id_ed25519
```

Then run the initialization:

```bash
# Set your HuggingFace token
export HF_TOKEN="your-huggingface-token-here"

# Set storage path (should match volume mount)
export MODEL_STORAGE_PATH="/runpod-volume/models"

# Run initialization script
bash /tmp/init_storage.sh
```

**⏱️ Time required:** 10-15 minutes (downloads ~43GB)

Expected output:

```
==========================================
Avatar API - Storage Initialization
==========================================

Configuration:
  Storage path: /runpod-volume/models
  HF_TOKEN: hf_xxxxx... (hidden)

Starting model downloads...
This will take 10-15 minutes on first run.

============================================================
Model: Wan 2.1 Image-to-Video 14B model
  Repo: Wan-AI/Wan2.1-I2V-14B-480P
  Size: ~40GB
  Destination: /runpod-volume/models/Wan2.1-I2V-14B-480P

  Downloading... (this may take several minutes)
✓ Downloaded in 298.3s (5.0 min)

[... similar output for other 2 models ...]

==========================================
✅ Storage Initialization Complete
==========================================

Models are ready at: /runpod-volume/models
Ready marker created: /runpod-volume/models/.storage_ready
```

### 3.4 Verify and Clean Up

```bash
# Verify models downloaded correctly
ls -lh /runpod-volume/models/
du -sh /runpod-volume/models/*

# Expected output:
# 40GB  /runpod-volume/models/Wan2.1-I2V-14B-480P
# 1.0GB /runpod-volume/models/chinese-wav2vec2-base
# 2.0GB /runpod-volume/models/InfiniteTalk

# Exit SSH
exit
```

**Terminate the init pod** - you no longer need it. The models are now in persistent storage.

1. Go to RunPod Pods console
2. Find your init pod
3. Click **Terminate**

**💰 Cost:** ~$0.10-0.20 for 15 minutes of GPU time (one-time cost)

## Step 4: Deploy to RunPod Serverless

### 4.1 Create Serverless Endpoint

1. Navigate to [RunPod Serverless](https://www.runpod.io/console/serverless)
2. Click **"+ New Endpoint"**
3. Configure basic settings:
   - **Endpoint Name:** `avatar-api-production`
   - **GPU Type:** Select **L40S** (48GB VRAM)
   - **Container Image:** `yourusername/avatar-api:v1.0`

### 4.2 Configure Environment Variables

In the **Environment Variables** section, add:

```bash
MODEL_STORAGE_PATH=/runpod-volume/models
```

**Note:** HF_TOKEN is no longer needed at runtime since models are pre-downloaded in Step 3.

### 4.3 Attach Persistent Volume

In the **Storage** section:

1. Toggle **"Enable Network Volume"**
2. Select your volume: `avatar-api-models` (the one you initialized in Step 3)
3. **Mount Path:** `/runpod-volume` (must match exactly)

### 4.4 Configure Scaling

In the **Scaling** section:

- **Min Workers:** `0` (scale-to-zero for cost savings)
- **Max Workers:** `5` (adjust based on expected load)
- **Idle Timeout:** `300` seconds (5 minutes)
- **Execution Timeout:** `600` seconds (10 minutes - includes model verification + generation)

**Rationale:**

- Min=0 ensures zero cost when idle
- Max=5 prevents runaway costs
- 600s timeout allows for PyTorch install + model verification + generation

### 4.5 Finalize and Deploy

1. Review all settings
2. Click **"Deploy"**
3. Wait for endpoint status: **Active**

**⏱️ Deployment time:** ~2-3 minutes

## Step 5: Verify Fast Startup

Since models are pre-downloaded, workers should start quickly.

### 5.1 Trigger First Worker

RunPod will auto-scale to 1 worker on first request. To trigger manually:

1. Go to your endpoint dashboard
2. Click **"Test Endpoint"** or wait for natural traffic

### 5.2 Monitor Container Startup

1. Click **"Logs"** tab in endpoint dashboard
2. Watch for quick startup:

```
==========================================
Avatar API - Container Starting
==========================================

Environment:
  Python version: Python 3.10.x
  Storage path: /runpod-volume/models

Installing PyTorch with CUDA 12.1...
✓ PyTorch installed

Verifying model availability...
============================================================
VERIFYING MODEL AVAILABILITY
============================================================
✓ Storage initialized: 2025-11-27T10:30:00Z
✓ Wan 2.1 Image-to-Video 14B model: 42 files
✓ Chinese Wav2Vec2 audio encoder: 15 files
✓ InfiniteTalk weights and audio conditioning: 8 files

============================================================
✅ ALL MODELS VERIFIED
============================================================

✅ Container Ready

Models verified at: /runpod-volume/models
```

**⏱️ Cold start time:** <60 seconds (PyTorch install + model verification)

**If you see errors about missing models**, storage initialization (Step 3) was not completed correctly. Return to Step 3 and re-run `init_storage.sh`.

### 5.3 Verify Model Paths

Check persistent volume contents:

1. SSH into container (via RunPod web terminal)
2. Run: `ls -lh /runpod-volume/models/`
3. Verify 3 directories exist:
   - `Wan2.1-I2V-14B-480P/` (~40GB)
   - `chinese-wav2vec2-base/` (~1GB)
   - `InfiniteTalk/` (~2GB)

## Step 5: Validate End-to-End Generation

Test InfiniteTalk generation manually to verify the pipeline works.

### 5.1 Access Container

1. In RunPod endpoint dashboard, click **"Connect"**
2. Choose **"Web Terminal"** or SSH

### 5.2 Prepare Test Inputs

You need:

- Test image (512x512 PNG or JPG)
- Test audio (WAV file, 5-10 seconds)

Example:

```bash
cd /app/InfiniteTalk

# Create test input JSON
cat > input.json <<EOF
{
  "prompt": "A woman passionately singing",
  "cond_video": "test_image.png",
  "cond_audio": {"person1": "test_audio.wav"}
}
EOF
```

### 5.3 Run InfiniteTalk Generation

```bash
python generate_infinitetalk.py \
  --task infinitetalk-14B \
  --size infinitetalk-720 \
  --ckpt_dir /runpod-volume/models/Wan2.1-I2V-14B-480P \
  --infinitetalk_dir /runpod-volume/models/InfiniteTalk \
  --wav2vec_dir /runpod-volume/models/chinese-wav2vec2-base \
  --input_json input.json \
  --save_file test_output \
  --num_persistent_param_in_dit 0
```

**Expected output:**

- Video generated at: `test_output.mp4`
- Resolution: 720p
- Duration: Matches audio length
- Generation time: 30-120 seconds

### 5.4 Download and Verify Video

1. Use RunPod file browser to download `test_output.mp4`
2. Verify:
   - Resolution: 1280x720 (720p)
   - Lip sync quality: Matches audio
   - No artifacts or color shifts

## Step 6: Test Container Restart (Cache Validation)

Verify models persist across restarts.

### 6.1 Scale Down to Zero

1. In endpoint dashboard, wait for idle timeout (5 min)
2. Verify worker count drops to 0

### 6.2 Trigger Cold Start

1. Send new request (or click "Test Endpoint")
2. Monitor logs for startup time

**Expected behavior:**

- Models NOT re-downloaded
- Logs show: "✓ All models already downloaded! Skipping download phase."
- Startup time: <60 seconds

### 6.3 Validate Cost Savings

Check RunPod billing dashboard:

- GPU charges: $0.00019/second × actual inference seconds only
- Storage charges: $4.30/month flat
- No idle GPU charges when workers = 0

## Environment Variables Reference

| Variable             | Required | Default                 | Description                                  |
| -------------------- | -------- | ----------------------- | -------------------------------------------- |
| `HF_TOKEN`           | Yes      | None                    | HuggingFace access token for model downloads |
| `MODEL_STORAGE_PATH` | No       | `/runpod-volume/models` | Path to persistent storage mount             |

## Troubleshooting

### Issue: Model download fails

**Symptoms:**

```
✗ Download attempt 1 failed: HTTPError 401
```

**Solution:**

1. Verify `HF_TOKEN` is set correctly
2. Check token has read permissions
3. Verify models are publicly accessible on HuggingFace

### Issue: Out of memory (OOM) errors

**Symptoms:**

```
RuntimeError: CUDA out of memory
```

**Solutions:**

1. Verify GPU type is L40S (48GB VRAM)
2. Add flag: `--num_persistent_param_in_dit 0` (VRAM optimization)
3. Consider switching to A100 (80GB) if still failing

### Issue: Container fails to start

**Symptoms:**

- Status: "Error" in dashboard
- No logs appearing

**Solutions:**

1. Check Docker image is accessible: `docker pull yourusername/avatar-api:v1.0`
2. Verify environment variables are set
3. Check persistent volume is attached correctly
4. Review RunPod system logs for deployment errors

### Issue: Slow cold starts (>60s)

**Symptoms:**

- Startup takes longer than expected
- Models already cached

**Solutions:**

1. Verify models are in persistent volume: `ls /runpod-volume/models/`
2. Check volume is attached correctly
3. Ensure model cache is not corrupted (delete and re-download if needed)

### Issue: Generation quality poor

**Symptoms:**

- Lip sync off
- Color shifts
- Artifacts in video

**Solutions:**

1. Verify input image quality (512x512, clear face)
2. Check audio clarity (WAV format recommended)
3. Test with different prompts
4. Ensure using 720p flag: `--size infinitetalk-720`

## Cost Breakdown

**First-time setup costs:**

- Persistent volume: $4.30/month (43GB storage)
- First model download: ~10 minutes GPU time = ~$0.11 (one-time)

**Ongoing costs (example workloads):**

| Usage              | GPU Time/Day | Monthly GPU Cost | Storage | Total/Month |
| ------------------ | ------------ | ---------------- | ------- | ----------- |
| 10 req/day × 60s   | 10 min       | $3.42            | $4.30   | **$7.72**   |
| 100 req/day × 60s  | 100 min      | $34.20           | $4.30   | **$38.50**  |
| 1000 req/day × 60s | 1000 min     | $342.00          | $4.30   | **$346.30** |

**GPU pricing:** L40S at $0.68/hour = $0.00019/second

## Next Steps

After successful deployment:

1. **Update endpoint in code:** Replace placeholder URL with your RunPod endpoint
2. **Implement API wrapper:** Move to Story 1.2 - Production API Development
3. **Set up monitoring:** Track GPU usage, costs, and error rates
4. **Configure alerts:** Cost thresholds, error rate spikes

## Additional Resources

- [RunPod Documentation](https://docs.runpod.io/)
- [InfiniteTalk GitHub](https://github.com/MeiGen-AI/InfiniteTalk)
- [HuggingFace Hub CLI](https://huggingface.co/docs/huggingface_hub/guides/cli)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-27
**Story:** 1.1 - RunPod Foundation & Model Setup
