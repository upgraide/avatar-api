# Avatar API - RunPod Pod Deployment Guide

Deploy the Avatar API on a RunPod Pod with local NVMe storage for reliable mmap support.

## Why Pod Instead of Serverless?

| Aspect | Serverless | Pod |
|--------|------------|-----|
| mmap support | No (network volumes) | Yes (local NVMe) |
| Cold start | 10+ min | None |
| Setup complexity | High | Low |
| Debugging | Hard | Easy (SSH) |
| Cost at 5 videos/day | ~$0.20 + headaches | ~$2-3/day |

**Bottom line:** For 236GB models, Pod is simpler and more reliable.

---

## Prerequisites

1. **RunPod Account** with payment method
2. **Models downloaded** to Pod storage (or plan ~30 min to download)
3. **Docker Hub** account (for pulling image)

---

## Quick Start

### Step 1: Create RunPod Pod

1. Go to [RunPod Pods](https://www.runpod.io/console/pods)
2. Click **Deploy** → **GPU Pods**
3. Select GPU: **L40S 48GB** (recommended) or A100/H100
4. Select Template: **RunPod Pytorch 2.4.1** (or any CUDA 12.1 template)
5. Set Volume: **100GB** minimum (for models + outputs)
6. Click **Deploy**

### Step 2: Download Models (First Time Only)

SSH into the Pod or use Web Terminal:

```bash
# Install huggingface-cli
pip install huggingface-hub

# Create models directory
mkdir -p /workspace/models

# Download models (~236GB, takes ~30 minutes)
huggingface-cli download Wan-AI/Wan2.1-I2V-14B-480P \
  --local-dir /workspace/models/Wan2.1-I2V-14B-480P

huggingface-cli download TencentGameMate/chinese-wav2vec2-base \
  --local-dir /workspace/models/chinese-wav2vec2-base

huggingface-cli download MeiGen-AI/InfiniteTalk \
  --local-dir /workspace/models/InfiniteTalk
```

### Step 3: Run the API Container

```bash
# Pull and run the Avatar API container
docker run -d \
  --name avatar-api \
  --gpus all \
  -p 8000:8000 \
  -v /workspace/models:/workspace/models \
  -e API_KEY="your-secret-api-key-here" \
  upgraide/avatar-api-pod:latest
```

### Step 4: Access the API

The API is accessible via RunPod proxy:

```
https://{POD_ID}-8000.proxy.runpod.net
```

Find your POD_ID in the RunPod dashboard.

---

## API Usage

### Health Check

```bash
curl https://{POD_ID}-8000.proxy.runpod.net/health
```

Response:
```json
{
  "status": "healthy",
  "model_path": "/workspace/models",
  "models": {
    "wan2.1": true,
    "wav2vec2": true,
    "infinitetalk": true
  }
}
```

### Generate Video

```bash
curl -X POST https://{POD_ID}-8000.proxy.runpod.net/generate \
  -H "Authorization: Bearer your-secret-api-key-here" \
  -F "image=@portrait.png" \
  -F "audio=@speech.wav" \
  -F "prompt=A person speaking naturally" \
  -F "size=infinitetalk-720" \
  -F "sample_steps=40" \
  --output video.mp4
```

**Parameters:**
- `image`: Portrait image (PNG/JPG)
- `audio`: Audio file (WAV/MP3)
- `prompt`: Scene description
- `size`: `infinitetalk-480` or `infinitetalk-720`
- `sample_steps`: 20 (fast) to 50 (quality)

### API Documentation

Interactive docs at: `https://{POD_ID}-8000.proxy.runpod.net/docs`

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `API_KEY` | (none) | API key for authentication |
| `MODEL_STORAGE_PATH` | `/workspace/models` | Path to models |
| `API_PORT` | `8000` | API server port |
| `ALLOWED_ORIGINS` | `*` | CORS allowed origins |

### Container Command

Full run command with all options:

```bash
docker run -d \
  --name avatar-api \
  --gpus all \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /workspace/models:/workspace/models \
  -v /workspace/outputs:/tmp/avatar-outputs \
  -e API_KEY="your-secret-api-key-here" \
  -e MODEL_STORAGE_PATH="/workspace/models" \
  -e ALLOWED_ORIGINS="https://yourdomain.com" \
  upgraide/avatar-api-pod:latest
```

---

## Cost Analysis

### RunPod Pod Costs (L40S GPU)

| Usage | Hours/Day | Cost/Day | Cost/Month |
|-------|-----------|----------|------------|
| Light (5 videos) | 2 hrs | $1.37 | $41 |
| Medium (20 videos) | 4 hrs | $2.74 | $82 |
| Heavy (50 videos) | 8 hrs | $5.47 | $164 |

**Pro tip:** Stop the Pod when not in use to save costs.

### Start/Stop via API

```bash
# Stop Pod (pause billing)
curl -X POST "https://api.runpod.io/v1/pods/{POD_ID}/stop" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY"

# Start Pod (resume)
curl -X POST "https://api.runpod.io/v1/pods/{POD_ID}/start" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY"
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check container logs
docker logs avatar-api

# Check if models exist
ls -la /workspace/models/
```

### "Models not found" Error

Models need to be downloaded first. Run the download commands from Step 2.

### GPU Not Detected

```bash
# Verify GPU is accessible
nvidia-smi

# Ensure --gpus all flag is used
docker run --gpus all ...
```

### Video Generation Fails

```bash
# Check container logs for errors
docker logs avatar-api --tail 50

# Try manual generation to debug
docker exec -it avatar-api bash
cd /app/InfiniteTalk
python generate_infinitetalk.py \
  --task infinitetalk-14B \
  --size infinitetalk-720 \
  --ckpt_dir /workspace/models/Wan2.1-I2V-14B-480P \
  --infinitetalk_dir /workspace/models/InfiniteTalk \
  --wav2vec_dir /workspace/models/chinese-wav2vec2-base \
  --input_json examples/single_example_image.json \
  --save_file /tmp/test
```

### API Timeout

Video generation takes 30-120 seconds. If timeouts occur:
- Increase client timeout
- Use `sample_steps=20` for faster generation
- Check GPU memory with `nvidia-smi`

---

## Updating the Container

```bash
# Pull latest image
docker pull upgraide/avatar-api-pod:latest

# Stop and remove old container
docker stop avatar-api
docker rm avatar-api

# Start new container
docker run -d \
  --name avatar-api \
  --gpus all \
  -p 8000:8000 \
  -v /workspace/models:/workspace/models \
  -e API_KEY="your-secret-api-key-here" \
  upgraide/avatar-api-pod:latest
```

---

## Security Notes

- Always set `API_KEY` in production
- Use HTTPS via RunPod proxy (automatic)
- Don't expose port 8000 directly to internet
- Rotate API keys periodically

---

## Next Steps

Once the Pod deployment is working:

1. **Story 2:** Add async job queue for multiple requests
2. **Story 3:** Add R2 storage for video persistence
3. **Future:** Consider serverless when volume justifies complexity
