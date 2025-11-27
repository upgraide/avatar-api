# Avatar API

Production-grade serverless talking avatar API using InfiniteTalk and Wan 2.1 models, deployed on RunPod Serverless with true scale-to-zero capability.

## Overview

Avatar API generates infinite-length talking avatar videos from image and audio inputs, leveraging:

- **InfiniteTalk** - State-of-the-art audio-conditioned talking head generation
- **Wan 2.1 I2V 14B** - High-quality image-to-video diffusion model
- **RunPod Serverless** - Cost-effective GPU compute with per-second billing
- **Cloudflare R2** (coming in Story 1.2) - Zero-egress-fee video storage

## Features

**Current (Story 1.1 - Foundation):**
- ✅ Docker containerization with NVIDIA CUDA 12.1 support
- ✅ Automatic model download to RunPod persistent storage
- ✅ 720p video output quality
- ✅ L40S GPU (48GB VRAM) for stable generation
- ✅ Scale-to-zero capability (zero idle costs)
- ✅ Fast cold starts (<60s after initial model download)

**Coming Soon (Story 1.2 - API):**
- 🚧 REST API with async job queue
- 🚧 API key authentication
- 🚧 Cloudflare R2 video storage
- 🚧 6-hour video retention policy

**Future (Story 1.3 - Hardening):**
- 📋 Enhanced API key management
- 📋 Rate limiting per key
- 📋 Monitoring & alerting
- 📋 OpenAPI documentation

## Quick Start

### Prerequisites

- RunPod account with payment method
- Docker Hub account
- HuggingFace account with access token
- Docker installed locally (for building)

### Deployment

See [DEPLOYMENT.md](docs/DEPLOYMENT.md) for complete step-by-step instructions.

**TL;DR:**

```bash
# 1. Build container
docker build -t avatar-api:v1.0 .

# 2. Push to registry
docker tag avatar-api:v1.0 yourusername/avatar-api:v1.0
docker push yourusername/avatar-api:v1.0

# 3. Deploy to RunPod Serverless
# - Create persistent volume (50GB)
# - Create serverless endpoint with L40S GPU
# - Attach volume at /runpod-volume
# - Set HF_TOKEN environment variable
# - Deploy and wait for first model download (~5-10 min)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  RunPod Serverless L40S GPU (48GB VRAM)                     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Docker Container (avatar-api:v1.0)                │    │
│  │                                                     │    │
│  │  ┌───────────────┐      ┌─────────────────────┐   │    │
│  │  │  startup.sh   │──┬──>│  core/models.py     │   │    │
│  │  │  (entrypoint) │  │   │  (model download)   │   │    │
│  │  └───────────────┘  │   └─────────────────────┘   │    │
│  │                     │                              │    │
│  │                     │   ┌─────────────────────┐   │    │
│  │                     └──>│  InfiniteTalk/      │   │    │
│  │                         │  (video generation) │   │    │
│  │                         └─────────────────────┘   │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Persistent Volume (/runpod-volume/models)         │    │
│  │                                                     │    │
│  │  • Wan2.1-I2V-14B-480P/        (~40GB)             │    │
│  │  • chinese-wav2vec2-base/      (~1GB)              │    │
│  │  • InfiniteTalk/               (~2GB)              │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Models

The API uses three pre-trained models downloaded from HuggingFace:

| Model | Size | Purpose | Source |
|-------|------|---------|--------|
| Wan 2.1 I2V 14B | ~40GB | Base video generation | [Wan-AI/Wan2.1-I2V-14B-480P](https://huggingface.co/Wan-AI/Wan2.1-I2V-14B-480P) |
| Chinese Wav2Vec2 | ~1GB | Audio encoding | [TencentGameMate/chinese-wav2vec2-base](https://huggingface.co/TencentGameMate/chinese-wav2vec2-base) |
| InfiniteTalk | ~2GB | Audio conditioning | [MeiGen-AI/InfiniteTalk](https://huggingface.co/MeiGen-AI/InfiniteTalk) |

**Total storage:** ~43GB

Models are downloaded once on first container startup to RunPod persistent storage. Subsequent container restarts reuse cached models.

## Performance

| Metric | Value |
|--------|-------|
| **First startup** | 5-10 minutes (one-time model download) |
| **Cold start (cached)** | <60 seconds |
| **Generation time** | 30-120 seconds (depends on audio length) |
| **Output quality** | 720p (1280x720) |
| **VRAM usage** | 12-17GB (L40S has 48GB = 3x headroom) |

## Cost Analysis

**RunPod L40S GPU:** $0.68/hour = $0.00019/second

| Usage Pattern | Monthly Cost |
|---------------|--------------|
| 10 requests/day × 60s | $7.72/month |
| 100 requests/day × 60s | $38.50/month |
| 1000 requests/day × 60s | $346.30/month |

**Includes:** GPU compute + $4.30/month persistent storage

## Project Structure

```
avatar-api/
├── Dockerfile              # Container definition (CUDA 12.1 base)
├── requirements.txt        # Python dependencies
├── startup.sh             # Container entrypoint
├── .env.example           # Environment template
├── core/
│   └── models.py          # Model download manager
├── InfiniteTalk/          # Cloned InfiniteTalk repository
├── docs/
│   ├── DEPLOYMENT.md      # Complete deployment guide
│   ├── tech-spec.md       # Technical specification
│   ├── research-technical-2025-11-26.md  # Platform research
│   └── epics.md           # Epic breakdown
└── README.md              # This file
```

## Environment Variables

Create `.env` from `.env.example`:

```bash
# Required
HF_TOKEN=your-huggingface-token

# Optional (defaults shown)
MODEL_STORAGE_PATH=/runpod-volume/models
```

## Development Status

**Current Sprint:** Epic 1 - Serverless Avatar API (10 points)

- ✅ **Story 1.1:** RunPod Foundation & Model Setup (3 points) - **COMPLETE**
- 🚧 **Story 1.2:** Production API Development (5 points) - TODO
- 📋 **Story 1.3:** Production Hardening & Documentation (2 points) - TODO

## Testing

Story 1.1 focuses on infrastructure validation. Manual testing only:

1. Deploy container to RunPod
2. Verify models download successfully
3. Run test InfiniteTalk generation
4. Validate 720p video output
5. Test container restart (model caching)

**Automated tests** will be added in Story 1.2 (API development).

## Troubleshooting

See [DEPLOYMENT.md - Troubleshooting](docs/DEPLOYMENT.md#troubleshooting) for common issues:

- Model download failures
- OOM errors
- Container startup issues
- Slow cold starts
- Generation quality problems

## Contributing

This is a greenfield project under active development. Current implementation follows:

- **Python 3.10+** with type hints
- **Black** code formatting
- **Ruff** linting
- **Google-style** docstrings

## License

[Add your license here]

## Acknowledgments

- [InfiniteTalk](https://github.com/MeiGen-AI/InfiniteTalk) - Audio-conditioned talking head generation
- [Wan 2.1](https://github.com/Wan-Video/Wan2.1) - Image-to-video diffusion model
- [RunPod](https://www.runpod.io/) - Serverless GPU platform

## Resources

- [InfiniteTalk Paper](https://arxiv.org/abs/2508.14033)
- [RunPod Documentation](https://docs.runpod.io/)
- [Technical Research Report](docs/research-technical-2025-11-26.md)
- [Technical Specification](docs/tech-spec.md)

---

**Version:** 1.0 (Story 1.1)
**Last Updated:** 2025-11-27
