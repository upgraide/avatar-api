# Docker Build Lessons Learned - 241GB Image with Embedded Models

This document explains the journey of building a 241GB Docker image with embedded AI models, including all failures encountered and the final working solution.

## Problem Statement

Build a Docker image containing:
- 236.5GB of AI models (Wan2.1-I2V-14B: 77GB, InfiniteTalk: 158GB, chinese-wav2vec2: 1.5GB)
- Python dependencies and application code (~5GB)
- Total final image size: ~241GB

**Target Platform:** RunPod Serverless (x86_64, CUDA 12.1)

---

## Failure Timeline & Root Causes

### Failure #1-5: Disk Space During Export (Day 1)

**Symptoms:**
- Build succeeded through all stages
- Downloaded all 236GB of models successfully
- Failed at final step: "exporting layers"
- Error: "no space left on device"

**Root Cause:**
- Build server had 601GB total disk
- During export, Docker needs:
  - Original layers: ~236GB
  - Temporary export files: ~241GB
  - Working space: ~50GB
  - **Total needed: ~527GB**
- Disk was 100% full at 599GB/601GB

**Solution Attempted:** Added 1TB Hetzner volume (104081408)

---

### Failure #6: Slow Export + Lease Timeout (After Adding 1TB Volume)

**Symptoms:**
- Build completed all stages successfully
- Export started but took 78 minutes (4701 seconds)
- Failed with: `lease does not exist: not found`
- Error: `failed to open writer: lease does not exist`

**Root Cause:**
We moved BOTH Docker data AND containerd to the 1TB network volume:
```bash
# What we did (WRONG):
/var/lib/docker -> /mnt/HC_Volume_104081408/docker     # OK (final image storage)
/var/lib/containerd -> /mnt/HC_Volume_104081408/containerd  # WRONG (too slow!)
```

**Why This Failed:**
1. **Network volume I/O is much slower than local NVMe**
2. Export process does intensive file operations on containerd
3. 78-minute export exceeded Docker's default lease timeout (~30-60 min)
4. Lease expired → build failed even though it would have completed

**Performance Impact:**
- Expected export time on local NVMe: 5-15 minutes
- Actual export time on network volume: 78 minutes (15x slower!)
- Network volume is optimized for capacity, not speed

---

## The Correct Solution

### Architecture

**Hybrid Storage Approach:**
```
Root Disk (601GB local NVMe - FAST):
├── /var/lib/containerd/          # ~33GB during build (needs speed)
└── OS + temporary files           # ~35GB

1TB Volume (network storage - LARGE):
└── /var/lib/docker/               # ~241GB final image (needs capacity)
```

**Why This Works:**
- **Containerd on NVMe:** Fast export (5-15 min instead of 78 min)
- **Docker data on 1TB volume:** Enough space for final 241GB image
- **Root disk has 542GB free:** Plenty for containerd's 33GB + temp files

---

## Step-by-Step Implementation

### Prerequisites

1. **Build Machine Requirements:**
   - 601GB+ local NVMe disk (root partition)
   - 1TB+ additional volume for final image storage
   - x86_64 architecture (for RunPod compatibility)
   - Good network connection (downloads 236GB from HuggingFace)

2. **Accounts:**
   - Docker Hub Pro account ($5/month for 241GB image)
   - HuggingFace access token

### Step 1: Prepare Storage

```bash
# SSH into build server
ssh -i ~/.ssh/id_ed25519 root@BUILD_SERVER_IP

# Check disk space
df -h /
# Should show: 601GB total, ~542GB free on /dev/sda1

# Check 1TB volume is mounted
df -h /mnt/HC_Volume_104081408
# Should show: 984GB total

# If volume is not full size, resize filesystem
resize2fs /dev/sdb
```

### Step 2: Configure Docker to Use Hybrid Storage

```bash
# Stop Docker
systemctl stop docker
systemctl stop containerd

# Create daemon.json to point Docker data-root to 1TB volume
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/mnt/HC_Volume_104081408/docker"
}
EOF

# Move existing Docker data to volume (if any)
if [ -d /var/lib/docker ]; then
  rsync -av /var/lib/docker/ /mnt/HC_Volume_104081408/docker/
  mv /var/lib/docker /var/lib/docker.backup
fi

# IMPORTANT: Leave containerd on root disk for speed
# Do NOT move /var/lib/containerd to the volume!

# Restart Docker
systemctl start containerd
systemctl start docker

# Verify configuration
docker info | grep "Docker Root Dir"
# Should show: /mnt/HC_Volume_104081408/docker

# Verify containerd is on root disk
ls -la /var/lib/containerd
# Should be a real directory, NOT a symlink
```

### Step 3: Run the Docker Build

```bash
# Navigate to project
cd /root/avatar-api

# Set HuggingFace token
export HF_TOKEN="your_huggingface_token_here"

# Run build (will take ~45 minutes total)
docker build \
  --build-arg HF_TOKEN=$HF_TOKEN \
  --platform linux/amd64 \
  -t upgraide/avatar-api:v1.0 \
  -t upgraide/avatar-api:latest \
  . 2>&1 | tee /tmp/docker-build.log

# Monitor in another terminal
tail -f /tmp/docker-build.log
```

### Step 4: Monitor Build Progress

**Expected Timeline:**
```
Stage 1 - Install Python deps:     10-15 min
Stage 2 - Download models (236GB):  20-30 min
  ├── Wan2.1-I2V-14B (77GB):       5 min
  ├── chinese-wav2vec2 (1.5GB):     <1 min
  └── InfiniteTalk (158GB):         15-20 min
Stage 3 - Copy models to runtime:   10-15 min
Stage 4 - Export image (241GB):     5-15 min ← CRITICAL (fast on NVMe)
──────────────────────────────────────────
Total:                              45-75 min
```

**Disk Usage During Build:**
```bash
# Monitor disk usage
watch -n 30 'df -h | grep -E "sda1|sdb"'

# Expected usage:
# /dev/sda1 (root): 35GB → 70GB (containerd temp files)
# /dev/sdb (1TB):   0GB → 241GB (final image)
```

### Step 5: Verify Build Success

```bash
# Check image was created
docker images | grep avatar-api
# Should show: upgraide/avatar-api  v1.0  <ID>  241GB

# Test image locally (requires GPU)
docker run --rm --gpus all upgraide/avatar-api:v1.0
# Should print: "✅ Container Ready"
```

### Step 6: Push to Docker Hub

```bash
# Login to Docker Hub
docker login
# Enter Docker Hub Pro credentials

# Push image (will take 2-6 hours depending on upload speed)
docker push upgraide/avatar-api:v1.0
docker push upgraide/avatar-api:latest

# Expected time by upload speed:
#   100 Mbps: ~5.5 hours
#   500 Mbps: ~1.1 hours
#   1 Gbps:   ~35 minutes
```

---

## Troubleshooting

### Export Takes > 30 Minutes

**Symptom:** Build hangs at "exporting layers" for >30 minutes

**Cause:** Containerd is on slow storage (network volume)

**Solution:**
```bash
# Check where containerd is located
ls -la /var/lib/containerd

# If it's a symlink to the volume, move it back:
systemctl stop docker
systemctl stop containerd
rm /var/lib/containerd  # Remove symlink
mv /var/lib/containerd.old /var/lib/containerd  # Restore from backup
systemctl start containerd
systemctl start docker

# Restart build
```

### "Lease Does Not Exist" Error

**Symptom:** Build fails with `lease does not exist: not found` during export

**Cause:** Export took too long (>60 min) and lease timed out

**Root Cause:** Containerd on slow storage

**Solution:** Move containerd back to root disk (see above)

### "No Space Left on Device" During Export

**Symptom:** Export fails halfway through with disk space error

**Diagnosis:**
```bash
# Check both disks
df -h | grep -E "sda1|sdb"

# Check containerd location
df /var/lib/containerd
```

**Solutions:**
1. If root disk full: Move containerd to volume (slow but works)
2. If 1TB volume full: Increase volume size or use cloud VM with larger disk
3. If both full: Clean up old images/containers:
   ```bash
   docker system prune -a
   docker volume prune
   ```

### Build Stuck at Model Download

**Symptom:** Download hangs or times out

**Cause:** HuggingFace rate limiting or token issues

**Solution:**
```bash
# Verify token
huggingface-cli whoami

# Check if models require approval:
# https://huggingface.co/Wan-AI/Wan2.1-I2V-14B-480P
# https://huggingface.co/MeiGen-AI/InfiniteTalk
# https://huggingface.co/TencentGameMate/chinese-wav2vec2-base

# Retry with resume
docker build --no-cache ...
```

---

## Cost Analysis

### One-Time Costs
- Hetzner CX51 (8 vCPU, 32GB RAM, 240GB NVMe): ~$0.50 for 5-hour build
- Hetzner 1TB volume: ~$0.10/day during build
- **Total one-time: ~$0.60**

### Monthly Costs
- Docker Hub Pro: $5/month (required for 241GB image)
- RunPod Serverless: $0.00019/second when running (L40S GPU)
  - Example: 100 hours/month = $68.40
- **Total monthly: ~$73/month**

### Savings vs Network Volume Approach
- Network volume approach: $43/month + slower performance
- Embedded model approach: $0/month storage + better performance
- **Savings: $43/month + faster cold starts**

---

## Performance Metrics

### Build Performance

| Stage | Local NVMe | Network Volume |
|-------|------------|----------------|
| Stage 1 (deps) | 10-15 min | 10-15 min |
| Stage 2 (models) | 20-30 min | 20-30 min |
| Stage 3 (copy) | 10-15 min | 10-15 min |
| Stage 4 (export) | **5-15 min** | **78 min** ⚠️ |
| **Total** | **45-75 min** | **118-138 min** |

**Key Insight:** Export is 10-15x slower on network volumes!

### RunPod Deployment Performance

- First worker start: 10-20 min (downloads 241GB image)
- Subsequent workers: <60s (RunPod caches image on hosts)
- Cold start (model load to GPU): ~10-15 min
- Video generation: 30-120s (depending on length)

---

## References

- **RunPod Best Practices:** https://docs.runpod.io/serverless/endpoints/endpoint-configurations#reducing-worker-startup-times
- **BuildKit Export Performance:** https://github.com/moby/buildkit/issues/1704
- **Docker Large Image Builds:** https://stackoverflow.com/questions/73208471/docker-build-issue-stuck-at-exporting-layers
- **Story 1.1 (RunPod Model Store):** `docs/sprint_artifacts/story-serverless-avatar-api-1.md`

---

## Summary

**What Works:**
✅ Containerd on local NVMe (fast export)
✅ Docker data-root on 1TB volume (enough space)
✅ Models embedded in image (RunPod best practice)
✅ Root disk cleanup freed 542GB

**What Doesn't Work:**
❌ Containerd on network volume (78 min export → timeout)
❌ All Docker data on root disk (out of space)
❌ RunPod Model Cache (only supports 1 model, we have 3)

**Final Architecture:**
```
Build Server:
├── Root NVMe (601GB):
│   ├── /var/lib/containerd (33GB) ← Speed critical
│   └── OS + temp (35GB)
│
└── 1TB Volume:
    └── /var/lib/docker (241GB) ← Capacity critical
```

This hybrid approach provides the speed of local NVMe where needed (export) and the capacity of network storage where needed (final image).
