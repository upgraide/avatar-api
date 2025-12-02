# Quick Build Reference - 241GB Docker Image

## TL;DR - What Works

```bash
# 1. Storage Setup (CRITICAL!)
#    - Containerd: Local NVMe (root disk) ← FAST export
#    - Docker data: 1TB volume           ← SPACE for image

# 2. Configure Docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/mnt/HC_Volume_104081408/docker"
}
EOF

# 3. DO NOT move containerd to volume!
#    Keep it at: /var/lib/containerd (on root NVMe)

# 4. Build
docker build \
  --build-arg HF_TOKEN=$HF_TOKEN \
  --platform linux/amd64 \
  -t upgraide/avatar-api:v1.0 \
  . 2>&1 | tee build.log
```

---

## Why Previous Attempts Failed

| Issue | Cause | Result |
|-------|-------|--------|
| Out of disk space | Root disk only 601GB, build needs ~527GB | Failed at export |
| Lease timeout | Containerd on slow network volume | 78 min export → timeout |

---

## The Correct Architecture

```
Root Disk (601GB local NVMe):
├── /var/lib/containerd/     # 33GB - MUST be here for speed
└── OS + temp                 # 35GB
    Total: ~70GB used, 530GB free ✓

1TB Volume (network storage):
└── /var/lib/docker/          # 241GB final image
    Total: 241GB used, 740GB free ✓
```

---

## Performance Comparison

| Configuration | Export Time | Success? |
|--------------|-------------|----------|
| All on root disk | N/A | ❌ Out of space |
| All on 1TB volume | 78 min | ❌ Lease timeout |
| **Hybrid (correct)** | **5-15 min** | ✅ **Works!** |

---

## Expected Timeline

```
Stage 1 - Python deps:      10-15 min
Stage 2 - Models (236GB):   20-30 min
Stage 3 - Copy to runtime:  10-15 min
Stage 4 - Export (FAST!):    5-15 min ← Key difference
───────────────────────────────────────
Total:                      45-75 min
```

---

## Troubleshooting

**Build hangs at "exporting layers"?**
```bash
# Check where containerd is:
ls -la /var/lib/containerd

# If it's a symlink → WRONG!
# Move it back to root disk:
systemctl stop docker containerd
rm /var/lib/containerd
mv /var/lib/containerd.old /var/lib/containerd
systemctl start containerd docker
```

**Out of space during export?**
```bash
# Check both disks:
df -h | grep -E "sda1|sdb"

# Need:
# /dev/sda1: 530GB+ free (for containerd + temp)
# /dev/sdb:  250GB+ free (for final image)
```

---

## Files to Read

1. `DOCKER_BUILD_LESSONS_LEARNED.md` - Full story with all failures
2. `BUILD_INSTRUCTIONS.md` - Detailed step-by-step guide
3. This file - Quick reference

---

## Key Insight

**Network volumes are optimized for CAPACITY, not SPEED.**

Export operations are I/O intensive and will timeout on slow storage.
Keep containerd on local NVMe for fast export, use volume only for final image storage.
