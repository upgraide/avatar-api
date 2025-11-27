# avatar-api - Technical Specification

**Author:** Boss
**Date:** 2025-11-26
**Project Level:** Quick Flow (Greenfield)
**Change Type:** New API Development
**Development Context:** Greenfield - New serverless talking avatar API

---

## Context

### Available Documents

**Research Documents Loaded:**
- ✅ Technical Research Report (research-technical-2025-11-26.md)
  - Platform decision: RunPod Serverless + L40S GPU (48GB VRAM)
  - Cost analysis: $7.42/month for 10 requests/day
  - InfiniteTalk viability confirmed (zero ComfyUI dependencies)
  - Docker containerization strategy validated
  - Implementation roadmap: 3-phase approach

**Key Insights from Research:**
- InfiniteTalk is production-ready standalone Python application
- No refactoring needed - clean API structure already exists
- RunPod offers 90% cost savings vs AWS SageMaker
- L40S GPU provides 3x safety margin (48GB vs 17GB minimum for 720p)
- True scale-to-zero capability with per-second billing

### Project Stack

**Current State:**
- Greenfield project (new codebase)
- InfiniteTalk repository cloned for reference
- No existing project dependencies yet

**Tech Stack to Establish:**

**Core Framework:**
- Python 3.10+ (required for InfiniteTalk compatibility)
- FastAPI 0.104.1 (modern async Python API framework)
- Uvicorn 0.24.0 (ASGI server)

**ML/Video Generation:**
- PyTorch 2.4.1 with CUDA 12.1 support
- diffusers 0.31.0+ (Hugging Face diffusers library)
- transformers 4.49.0+ (for audio processing)
- InfiniteTalk dependencies (from cloned repo requirements.txt)

**Infrastructure:**
- Docker (containerization)
- RunPod Serverless (GPU compute platform)
- Cloudflare R2 (S3-compatible storage for video outputs)

**Development:**
- pytest 7.4.3 (testing framework)
- black 23.11.0 (code formatting)
- ruff 0.1.6 (fast Python linter)

### Existing Codebase Structure

**Greenfield Project - Establishing New Structure:**

Proposed directory structure:
```
avatar-api/
├── api/                    # FastAPI application
│   ├── main.py            # API entry point
│   ├── routes/            # API route handlers
│   ├── models/            # Pydantic models
│   ├── services/          # Business logic
│   └── middleware/        # Auth, logging, etc.
├── core/                   # Core video generation logic
│   ├── infinitetalk.py    # InfiniteTalk wrapper
│   ├── storage.py         # R2 storage client
│   └── queue.py           # Job queue manager
├── tests/                  # Test suite
│   ├── test_api.py
│   ├── test_generation.py
│   └── fixtures/
├── InfiniteTalk/          # Cloned repository (reference)
├── Dockerfile             # Container definition
├── requirements.txt       # Python dependencies
├── .env.example          # Environment template
└── README.md             # Project documentation
```

---

## The Change

### Problem Statement

**Current Challenge:**
Transitioning from a fragile ComfyUI prototype to a production-grade serverless API for infinite-length talking avatar generation.

**Pain Points:**
1. **ComfyUI prototype limitations:**
   - Manual node management (not automatable)
   - Fragile and prone to breaking
   - Not suitable for production SaaS integration

2. **Cost inefficiency:**
   - Always-on infrastructure (costly when idle)
   - No auto-scaling capability
   - Poor economics for low-volume SaaS

3. **Technical debt:**
   - No API layer
   - No authentication
   - No job queue or async processing
   - No storage management

**Business Impact:**
- Cannot launch production SaaS offering
- High infrastructure costs even with zero users
- Poor developer experience for integration

### Proposed Solution

Build a production-grade, serverless talking avatar API with the following architecture:

**Core Components:**
1. **FastAPI REST API** - Clean HTTP interface for video generation
2. **Docker Container** - Packages InfiniteTalk + models for deployment
3. **RunPod Serverless** - GPU compute (L40S 48GB) with scale-to-zero
4. **Cloudflare R2** - Cost-effective video storage (no egress fees)
5. **Basic API Key Auth** - Simple but secure authentication

**User Flow:**
1. Client POSTs image + audio + API key to `/generate`
2. API validates input, creates job, returns job_id
3. Async worker generates video using InfiniteTalk on RunPod GPU
4. Video uploaded to R2, presigned URL generated
5. Client polls `/status/{job_id}` until complete
6. Client retrieves video via `/result/{job_id}` presigned URL
7. Videos auto-deleted after 6 hours

**Key Benefits:**
- Zero idle costs (pay-per-second GPU usage)
- Handles multiple concurrent users via queue
- Production-ready from day 1 (auth, monitoring, error handling)
- $7-38/month cost for 10-100 requests/day

### Scope

**In Scope:**

**Story 1 - Week 1 POC (Foundation):**
- Clone InfiniteTalk repository
- Create Dockerfile (lightweight, models NOT baked in)
- Build and push container to Docker Hub
- Deploy to RunPod Serverless (L40S GPU)
- Configure RunPod persistent storage for models
- First startup: Download 3 models (Wan 2.1 14B, Wav2Vec2, InfiniteTalk weights)
- Validate end-to-end video generation (720p)
- Document deployment process

**Story 2 - Week 2 Production API:**
- FastAPI application with 3 endpoints:
  - `POST /generate` - Submit job (requires API key)
  - `GET /status/{job_id}` - Check job status
  - `GET /result/{job_id}` - Get video presigned URL
- Basic API key authentication (env variable initially)
- In-memory job queue with async processing
- Cloudflare R2 integration:
  - Upload generated videos
  - Generate 6-hour presigned URLs
  - Auto-cleanup after 6 hours
- Error handling and structured logging
- Input validation (image/audio formats, size limits)
- Health check endpoint (`GET /health`)

**Story 3 - Production Hardening:**
- Enhanced API key management (database-backed)
- Rate limiting (per API key)
- Monitoring and alerting:
  - GPU utilization tracking
  - Generation time metrics
  - Error rate monitoring
  - Cost tracking
- API documentation (OpenAPI/Swagger)
- Deployment documentation
- Basic CI/CD pipeline (GitHub Actions)

**Out of Scope (Future Work):**
- Advanced authentication (OAuth2, JWT) - basic API keys only for now
- Multiple video quality options - 720p only initially
- Batch processing - single video requests only
- Custom model fine-tuning
- User dashboard or admin panel
- Webhook callbacks (polling only for status)
- Video thumbnails or previews
- Advanced cost optimization beyond scale-to-zero

---

## Implementation Details

### Source Tree Changes

**Files to CREATE:**

**API Layer:**
- `api/main.py` - CREATE - FastAPI application entry point with CORS, middleware
- `api/routes/generate.py` - CREATE - POST /generate endpoint, input validation
- `api/routes/status.py` - CREATE - GET /status/{job_id} endpoint
- `api/routes/result.py` - CREATE - GET /result/{job_id} endpoint with presigned URL
- `api/routes/health.py` - CREATE - GET /health endpoint for monitoring
- `api/models/requests.py` - CREATE - Pydantic models for request validation
- `api/models/responses.py` - CREATE - Pydantic models for API responses
- `api/middleware/auth.py` - CREATE - API key authentication middleware
- `api/middleware/logging.py` - CREATE - Request/response logging middleware

**Core Services:**
- `core/infinitetalk.py` - CREATE - Wrapper around InfiniteTalk generate_infinitetalk.py
- `core/storage.py` - CREATE - Cloudflare R2 client (S3-compatible)
- `core/queue.py` - CREATE - In-memory job queue with async worker
- `core/cleanup.py` - CREATE - Scheduled task for 6-hour video cleanup
- `core/models.py` - CREATE - Model download and management for RunPod storage

**Configuration:**
- `Dockerfile` - CREATE - Multi-stage build for production container
- `requirements.txt` - CREATE - Python dependencies (FastAPI + InfiniteTalk deps)
- `.env.example` - CREATE - Environment variable template
- `config.py` - CREATE - Application configuration management

**Testing:**
- `tests/test_api.py` - CREATE - API endpoint tests
- `tests/test_generation.py` - CREATE - Video generation integration tests
- `tests/test_storage.py` - CREATE - R2 storage tests
- `tests/conftest.py` - CREATE - Pytest fixtures and configuration

**Documentation:**
- `README.md` - CREATE - Project overview, setup instructions
- `docs/API.md` - CREATE - API endpoint documentation
- `docs/DEPLOYMENT.md` - CREATE - RunPod deployment guide
- `.github/workflows/deploy.yml` - CREATE - CI/CD pipeline

**No MODIFY or DELETE operations - greenfield project**

### Technical Approach

**1. Container Architecture:**

Use **lightweight Dockerfile** without baked-in models:
```dockerfile
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

# Install Python 3.10
RUN apt-get update && apt-get install -y python3.10 python3-pip ffmpeg git

# Copy application code
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy API and core modules
COPY api/ ./api/
COPY core/ ./core/
COPY InfiniteTalk/ ./InfiniteTalk/

# Expose API port
EXPOSE 8000

# Startup script handles model download on first run
CMD ["python", "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**2. Model Management Strategy:**

On first container startup:
- Check if models exist in RunPod persistent storage (`/runpod-volume/models/`)
- If missing, download using Hugging Face CLI:
  - Wan 2.1 I2V 14B (~40GB)
  - chinese-wav2vec2-base (~1GB)
  - InfiniteTalk weights (~2GB)
- Store in persistent volume (survives container restarts)
- Cost: $4.30/month for 43GB storage
- Subsequent starts: Mount existing storage (fast <60s cold start)

**3. API Design:**

RESTful API using FastAPI with async/await:
- **Authentication:** Bearer token in Authorization header
- **Request format:** multipart/form-data (image file + audio file + JSON metadata)
- **Response format:** JSON with job_id or status/result
- **Error handling:** Standard HTTP status codes + structured error responses

**4. Job Queue Pattern:**

In-memory queue (asyncio.Queue) for MVP:
- Submit job → returns immediately with job_id
- Background worker picks up jobs sequentially
- Status tracked in-memory dict: {job_id: {status, progress, result_url, error}}
- Future: Migrate to Redis for persistence and multi-worker support

**5. Storage Integration:**

Cloudflare R2 (S3-compatible):
- Use boto3 S3 client with R2 endpoint
- Upload pattern: `videos/{job_id}.mp4`
- Generate presigned GET URL (6-hour expiry)
- Scheduled cleanup job deletes files older than 6 hours
- No egress fees (unlike S3)

**6. Video Generation:**

Call InfiniteTalk's `generate_infinitetalk.py` programmatically:
```python
import subprocess
import json

# Create input JSON
input_data = {
    "prompt": user_prompt,
    "cond_video": image_path,
    "cond_audio": {"person1": audio_path}
}

# Call InfiniteTalk
subprocess.run([
    "python", "InfiniteTalk/generate_infinitetalk.py",
    "--task", "infinitetalk-14B",
    "--size", "infinitetalk-720",
    "--ckpt_dir", "/runpod-volume/models/Wan2.1-I2V-14B-480P",
    "--infinitetalk_dir", "/runpod-volume/models/InfiniteTalk",
    "--wav2vec_dir", "/runpod-volume/models/chinese-wav2vec2-base",
    "--input_json", "input.json",
    "--save_file", output_path
])
```

**7. Deployment Platform:**

RunPod Serverless configuration:
- GPU: L40S 48GB VRAM
- Container source: Docker Hub (public or private registry)
- Environment variables: API keys, R2 credentials
- Persistent volume: 50GB mounted at `/runpod-volume/`
- Min workers: 0 (true scale-to-zero)
- Max workers: 5 (cost control)
- Timeout: 600 seconds (10 min max per request)

### Existing Patterns to Follow

**Greenfield project - establishing new patterns:**

**Code Style:**
- Python 3.10+ type hints everywhere
- Black formatter (line length 100)
- Ruff linter with strict settings
- Docstrings: Google style

**API Patterns:**
- FastAPI dependency injection for auth
- Pydantic v2 for validation
- Async/await for all I/O operations
- Structured logging (JSON format)

**Error Handling:**
- Custom exception classes inherit from base APIException
- HTTP exception handlers return consistent JSON format
- Log all errors with context (job_id, user_id, traceback)

**Testing:**
- Pytest with async support
- Fixtures for common test data
- Integration tests use Docker testcontainers
- 80%+ coverage target

**File Naming:**
- Snake_case for Python files
- Clear, descriptive names (no abbreviations)
- Test files mirror source: `test_{module_name}.py`

### Integration Points

**External Services:**

1. **RunPod Serverless API:**
   - Container deployment and management
   - GPU resource allocation
   - Persistent storage mounting
   - No direct API calls from application code

2. **Cloudflare R2:**
   - Endpoint: Account-specific R2 endpoint
   - Authentication: Access Key ID + Secret Access Key
   - Operations: PutObject, GetObject, DeleteObject, GeneratePresignedUrl
   - SDK: boto3 with S3 compatibility

3. **Hugging Face Hub (model downloads):**
   - Authentication: HF_TOKEN environment variable
   - CLI tool: `huggingface-cli download`
   - One-time download on first startup

**Internal Module Dependencies:**

- `api.routes.*` → depends on → `core.infinitetalk`, `core.storage`, `core.queue`
- `core.infinitetalk` → depends on → InfiniteTalk repository code
- `core.storage` → standalone (R2 client only)
- `core.queue` → standalone (in-memory queue)
- `core.cleanup` → depends on → `core.storage`

**Data Flow:**
1. Client → FastAPI routes (HTTP)
2. Routes → Queue service (in-process async)
3. Queue worker → InfiniteTalk wrapper (subprocess)
4. InfiniteTalk → GPU inference (CUDA)
5. Output video → R2 storage (boto3/S3)
6. R2 URL → Client (presigned URL)

---

## Development Context

### Relevant Existing Code

**InfiniteTalk Repository (Reference):**
- `InfiniteTalk/generate_infinitetalk.py` - Main entry point for video generation
- `InfiniteTalk/wan/multitalk.py` - InfiniteTalkPipeline class (lines 1-650)
- `InfiniteTalk/requirements.txt` - ML dependencies to incorporate
- `InfiniteTalk/examples/single_example_image.json` - Input format reference

**Key patterns to reference:**
- Input JSON structure from examples/
- Command-line arguments for generate_infinitetalk.py
- Error handling patterns in wan/multitalk.py

### Dependencies

**Framework/Libraries:**

**FastAPI Stack:**
- fastapi==0.104.1 - Modern async web framework
- uvicorn[standard]==0.24.0 - ASGI server with auto-reload
- pydantic==2.5.0 - Data validation using Python type hints
- python-multipart==0.0.6 - Form data parsing

**Storage:**
- boto3==1.29.7 - AWS SDK (R2 compatibility)
- botocore==1.32.7 - Low-level AWS interface

**InfiniteTalk Dependencies (from requirements.txt):**
- torch==2.4.1 (with CUDA 12.1)
- diffusers>=0.31.0
- transformers>=4.49.0
- opencv-python>=4.9.0.80
- imageio, imageio-ffmpeg
- librosa, pyloudnorm (audio processing)
- gradio>=5.0.0 (optional - can remove for API-only)

**Development:**
- pytest==7.4.3 - Testing framework
- pytest-asyncio==0.21.1 - Async test support
- httpx==0.25.2 - Async HTTP client for testing
- black==23.11.0 - Code formatter
- ruff==0.1.6 - Fast linter

### Internal Modules

**Core Modules (to be created):**
- `core.infinitetalk` - InfiniteTalkService class
  - Methods: generate_video(image, audio, prompt) → video_path
  - Handles subprocess calls to InfiniteTalk

- `core.storage` - R2StorageService class
  - Methods: upload(file_path) → url, delete(file_path), cleanup_old()
  - S3-compatible operations

- `core.queue` - JobQueue class
  - Methods: submit(job), get_status(job_id), process_jobs()
  - In-memory queue with async worker

- `core.models` - ModelManager class
  - Methods: ensure_models_downloaded(), get_model_paths()
  - One-time setup on first container start

**API Modules:**
- `api.routes.generate` - Job submission endpoint
- `api.routes.status` - Status polling endpoint
- `api.routes.result` - Result retrieval endpoint
- `api.middleware.auth` - API key validation
- `api.models.requests` - GenerateRequest, etc.
- `api.models.responses` - JobResponse, StatusResponse, etc.

### Configuration Changes

**Environment Variables (.env):**
```bash
# API Configuration
API_KEY=your-secret-api-key-here
ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com

# Cloudflare R2
R2_ACCOUNT_ID=your-account-id
R2_ACCESS_KEY_ID=your-access-key
R2_SECRET_ACCESS_KEY=your-secret-key
R2_BUCKET_NAME=avatar-videos

# RunPod Storage
MODEL_STORAGE_PATH=/runpod-volume/models
VIDEO_RETENTION_HOURS=6

# Hugging Face (for model downloads)
HF_TOKEN=your-huggingface-token

# Logging
LOG_LEVEL=INFO
```

**Docker Environment Variables:**
- Set in RunPod dashboard
- Sensitive values use RunPod secrets feature
- Non-sensitive defaults in Dockerfile ENV directives

**No config files to modify - all configuration via environment variables**

### Existing Conventions (Brownfield)

Greenfield project - establishing new conventions:

**Python Style:**
- PEP 8 compliance via Black + Ruff
- Type hints mandatory for all functions
- Docstrings for all public APIs (Google style)
- Imports organized: stdlib → third-party → local

**Git Workflow:**
- Feature branches: `feature/story-{N}-{description}`
- Commit messages: Conventional Commits format
- PR required for main branch
- Squash merge to keep history clean

**API Conventions:**
- RESTful resource naming (plural nouns)
- HTTP status codes: 200 (OK), 201 (Created), 400 (Bad Request), 401 (Unauthorized), 500 (Server Error)
- Error responses: `{"error": {"code": "INVALID_INPUT", "message": "...", "details": {}}}`
- Success responses: `{"data": {...}, "meta": {}}`

### Test Framework & Standards

**Testing Framework:**
- pytest 7.4.3 (async support via pytest-asyncio)

**Test Organization:**
```
tests/
├── conftest.py          # Shared fixtures
├── test_api.py          # API endpoint tests
├── test_generation.py   # Video generation tests
├── test_storage.py      # R2 storage tests
├── test_queue.py        # Job queue tests
└── fixtures/
    ├── test_image.png
    └── test_audio.wav
```

**Coverage Requirements:**
- Minimum 80% overall coverage
- 100% coverage for core business logic
- Integration tests for happy path + major error cases
- Skip coverage for InfiniteTalk library code (external)

**Testing Patterns:**
- Use `pytest.mark.asyncio` for async tests
- Mock external services (R2, RunPod) in unit tests
- Use Docker testcontainers for integration tests
- Fixtures for auth headers, test files, etc.

---

## Implementation Stack

**Runtime Environment:**
- Python 3.10+ (Ubuntu 22.04 base)
- CUDA 12.1 + cuDNN 8 (NVIDIA runtime)
- FFmpeg 4.4+ (video processing)

**Core Framework:**
- FastAPI 0.104.1 (async web framework)
- Uvicorn 0.24.0 (ASGI server)
- Pydantic 2.5.0 (data validation)

**ML/Video Stack:**
- PyTorch 2.4.1 (with CUDA support)
- diffusers 0.31.0 (Hugging Face)
- transformers 4.49.0 (Hugging Face)
- InfiniteTalk dependencies (complete list in requirements.txt)

**Storage & Compute:**
- Cloudflare R2 (via boto3 S3-compatible API)
- RunPod Serverless L40S GPU (48GB VRAM)
- RunPod persistent storage (50GB volume)

**Development Tools:**
- pytest 7.4.3 + pytest-asyncio 0.21.1 (testing)
- black 23.11.0 (formatting)
- ruff 0.1.6 (linting)
- httpx 0.25.2 (async HTTP client for tests)

**Deployment:**
- Docker (containerization)
- GitHub Actions (CI/CD)
- Docker Hub (container registry)

---

## Technical Details

**Video Generation Pipeline:**

1. **Input Processing:**
   - Accept image (PNG/JPG, max 10MB)
   - Accept audio (WAV/MP3, max 50MB)
   - Validate formats using PIL + librosa
   - Save to temporary files on RunPod storage

2. **InfiniteTalk Invocation:**
   - Create input JSON with prompt, image path, audio path
   - Call `generate_infinitetalk.py` via subprocess
   - Arguments:
     - `--task infinitetalk-14B`
     - `--size infinitetalk-720` (720p output)
     - `--ckpt_dir` → Wan 2.1 model path
     - `--infinitetalk_dir` → InfiniteTalk weights path
     - `--wav2vec_dir` → Wav2Vec2 model path
     - `--num_persistent_param_in_dit 0` (VRAM optimization)
   - Monitor subprocess for errors
   - Capture stdout/stderr for debugging

3. **Output Processing:**
   - InfiniteTalk generates MP4 file
   - Upload to R2 immediately
   - Delete local temp files
   - Generate 6-hour presigned URL
   - Update job status with result URL

**Performance Considerations:**

- **Generation Time:** 30-120 seconds per video (depends on audio length)
- **Cold Start:** First container start: ~5-10 min (model download), subsequent: <60s
- **Concurrency:** Sequential processing initially (1 video at a time per worker)
- **VRAM Usage:** 12-17GB for 720p, L40S has 48GB (3x headroom)
- **Storage:** Videos average 50-200MB (720p, 30-60s duration)

**Error Scenarios:**

1. **Invalid Input:**
   - Unsupported image format → 400 Bad Request
   - Audio too long (>5 min) → 400 Bad Request
   - File size exceeded → 413 Payload Too Large

2. **Generation Failures:**
   - OOM error → Retry with 480p fallback
   - InfiniteTalk subprocess crash → Log error, mark job failed
   - Timeout (>10 min) → Kill subprocess, mark failed

3. **Storage Failures:**
   - R2 upload fails → Retry 3 times with exponential backoff
   - Presigned URL generation fails → Return error, keep video for manual recovery

4. **Auth Failures:**
   - Missing API key → 401 Unauthorized
   - Invalid API key → 401 Unauthorized
   - Rate limit exceeded → 429 Too Many Requests

**Security Considerations:**

- **API Keys:** Store securely (env vars, not in code)
- **Input Validation:** Strict file type and size checks
- **Path Traversal:** Sanitize all file paths
- **CORS:** Restrict origins to allowed domains
- **Rate Limiting:** Per-API-key limits to prevent abuse
- **Logs:** Never log sensitive data (API keys, tokens)

**Edge Cases:**

- Empty audio file → Reject with validation error
- Non-English audio → Works (Wav2Vec2 is multilingual-capable)
- Very short audio (<1s) → May produce low-quality output, allow but warn
- Concurrent same job_id → Prevent with UUID generation
- R2 storage full → Implement cleanup before upload
- Model download fails → Retry with exponential backoff, max 3 attempts

---

## Development Setup

**Prerequisites:**
- Python 3.10+
- Docker with NVIDIA Container Runtime (for local GPU testing)
- Git
- Cloudflare account (for R2 access)
- RunPod account
- Hugging Face account (for model downloads)

**Local Development Setup:**

```bash
# 1. Clone repository
git clone <your-repo-url>
cd avatar-api

# 2. Create Python virtual environment
python3.10 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Copy environment template
cp .env.example .env
# Edit .env with your credentials

# 5. (Optional) Download models locally if you have GPU + storage
# Note: This requires ~43GB disk space and GPU for testing
python core/models.py --download

# 6. Run API locally (without GPU - will fail on generation)
uvicorn api.main:app --reload --port 8000

# 7. Run tests
pytest

# 8. Format code
black .
ruff check .
```

**Docker Development:**

```bash
# Build container
docker build -t avatar-api:dev .

# Run container locally (requires NVIDIA GPU)
docker run --gpus all -p 8000:8000 \
  -v $(pwd)/models:/runpod-volume/models \
  --env-file .env \
  avatar-api:dev

# Test API
curl -X POST http://localhost:8000/generate \
  -H "Authorization: Bearer your-api-key" \
  -F "image=@test_image.png" \
  -F "audio=@test_audio.wav" \
  -F "prompt=A woman singing"
```

**Note:** Full local testing requires NVIDIA GPU with 48GB+ VRAM. Most development can be done with RunPod deployment for actual video generation testing.

---

## Implementation Guide

### Setup Steps

**Pre-Implementation Checklist:**

1. **Account Setup:**
   - [ ] Create RunPod account, add payment method
   - [ ] Create Cloudflare account, set up R2 bucket
   - [ ] Create Hugging Face account, generate access token
   - [ ] Create Docker Hub account (or use GitHub Container Registry)

2. **Repository Setup:**
   - [ ] Initialize Git repository
   - [ ] Create `.gitignore` (exclude .env, models/, *.mp4)
   - [ ] Set up branch protection on main
   - [ ] Configure GitHub Actions secrets

3. **Development Environment:**
   - [ ] Install Python 3.10+
   - [ ] Install Docker
   - [ ] Clone InfiniteTalk repository to project
   - [ ] Create virtual environment
   - [ ] Install dependencies

4. **Configuration:**
   - [ ] Generate secure API key (use `secrets.token_urlsafe(32)`)
   - [ ] Configure R2 bucket with CORS policy
   - [ ] Set up RunPod persistent volume (50GB)
   - [ ] Document all credentials in password manager

### Implementation Steps

**Organized by Story:**

**Story 1 - Week 1 POC:**

1. **Day 1-2: Docker Setup**
   - Create Dockerfile (NVIDIA CUDA base)
   - Add InfiniteTalk dependencies to requirements.txt
   - Create model download script (core/models.py)
   - Build container locally (without models)
   - Test container starts successfully

2. **Day 3: RunPod Configuration**
   - Create RunPod persistent volume (50GB)
   - Upload container to Docker Hub
   - Deploy to RunPod Serverless (L40S GPU)
   - Configure environment variables
   - Trigger model download on first start

3. **Day 4-5: Validation**
   - SSH into RunPod container
   - Manually test InfiniteTalk generation
   - Verify 720p output quality
   - Measure generation time baseline
   - Document deployment steps

**Story 2 - Week 2 Production API:**

1. **Day 1-2: Core API Development**
   - Create FastAPI app structure (api/main.py)
   - Implement /generate endpoint with validation
   - Implement /status and /result endpoints
   - Add basic API key middleware
   - Create Pydantic models for requests/responses

2. **Day 3: Background Processing**
   - Implement job queue (core/queue.py)
   - Create InfiniteTalk wrapper (core/infinitetalk.py)
   - Wire up async worker to process jobs
   - Add error handling and logging

3. **Day 4: Storage Integration**
   - Implement R2 client (core/storage.py)
   - Add video upload after generation
   - Generate presigned URLs (6-hour expiry)
   - Implement cleanup task

4. **Day 5: Testing & Deployment**
   - Write API tests (test_api.py)
   - Test end-to-end flow locally
   - Deploy updated container to RunPod
   - Validate production API works

**Story 3 - Production Hardening:**

1. **Enhanced Auth & Rate Limiting**
   - Database-backed API key storage
   - Per-key rate limiting (Redis-based)

2. **Monitoring & Alerting**
   - Set up logging aggregation
   - Add Prometheus metrics
   - Configure cost alerts

3. **Documentation & CI/CD**
   - Write API documentation (OpenAPI)
   - Create deployment guide
   - Set up GitHub Actions workflow

### Testing Strategy

**Unit Tests:**
- API route handlers (mock core services)
- Input validation logic
- Storage client operations (mock boto3)
- Queue operations (in-memory, no mocks needed)

**Integration Tests:**
- Full API flow with test fixtures
- R2 upload/download/delete cycle
- Job queue end-to-end
- (Optional) InfiniteTalk generation with small test inputs

**Manual Testing:**
- Deploy to RunPod staging environment
- Test with real image + audio inputs
- Verify 720p video quality
- Test error scenarios (invalid inputs, auth failures)
- Load testing with concurrent requests

**Test Data:**
- `tests/fixtures/test_image.png` - 512x512 portrait
- `tests/fixtures/test_audio.wav` - 10s speech sample
- Expected output: ~10s video, 720p, <100MB

### Acceptance Criteria

**Story 1 - POC Complete When:**
1. ✅ Container builds successfully without errors
2. ✅ Deploys to RunPod Serverless (L40S GPU)
3. ✅ Models download to persistent storage on first start
4. ✅ Subsequent starts complete in <60 seconds
5. ✅ InfiniteTalk generates 720p video from test inputs
6. ✅ Video quality matches research expectations
7. ✅ Deployment documented in docs/DEPLOYMENT.md

**Story 2 - API Complete When:**
1. ✅ POST /generate accepts image + audio, returns job_id
2. ✅ API key authentication works (401 for invalid keys)
3. ✅ GET /status returns correct job progress
4. ✅ GET /result returns valid presigned R2 URL
5. ✅ Videos accessible via presigned URL for 6 hours
6. ✅ Videos auto-deleted after 6 hours
7. ✅ Concurrent requests queue properly
8. ✅ Errors return structured JSON responses
9. ✅ API tests pass with 80%+ coverage
10. ✅ Production deployment functional

**Story 3 - Hardening Complete When:**
1. ✅ Enhanced API key management implemented
2. ✅ Rate limiting prevents abuse (429 status)
3. ✅ Monitoring dashboards show key metrics
4. ✅ Cost tracking alerts configured
5. ✅ API documentation published (OpenAPI/Swagger)
6. ✅ Deployment guide complete
7. ✅ CI/CD pipeline runs tests on PR

---

## Developer Resources

### File Paths Reference

**Application Code:**
- `/api/main.py` - FastAPI application entry point
- `/api/routes/generate.py` - POST /generate endpoint
- `/api/routes/status.py` - GET /status/{job_id} endpoint
- `/api/routes/result.py` - GET /result/{job_id} endpoint
- `/api/routes/health.py` - GET /health endpoint
- `/api/middleware/auth.py` - API key authentication
- `/api/models/requests.py` - Request Pydantic models
- `/api/models/responses.py` - Response Pydantic models
- `/core/infinitetalk.py` - InfiniteTalk wrapper service
- `/core/storage.py` - Cloudflare R2 client
- `/core/queue.py` - In-memory job queue
- `/core/cleanup.py` - Video cleanup task
- `/core/models.py` - Model download manager

**Configuration:**
- `/Dockerfile` - Container definition
- `/requirements.txt` - Python dependencies
- `/.env.example` - Environment variable template
- `/config.py` - Application config management

**Tests:**
- `/tests/test_api.py` - API endpoint tests
- `/tests/test_generation.py` - Video generation tests
- `/tests/test_storage.py` - R2 storage tests
- `/tests/conftest.py` - Pytest fixtures

**Documentation:**
- `/README.md` - Project overview
- `/docs/API.md` - API documentation
- `/docs/DEPLOYMENT.md` - Deployment guide

### Key Code Locations

**Authentication:**
- API key validation: `api/middleware/auth.py:15-35`

**Request Handling:**
- Generate endpoint: `api/routes/generate.py:20-60`
- Input validation: `api/models/requests.py:10-25`

**Video Generation:**
- InfiniteTalk wrapper: `core/infinitetalk.py:40-120`
- Subprocess call: `core/infinitetalk.py:85-100`

**Storage:**
- R2 upload: `core/storage.py:30-50`
- Presigned URL: `core/storage.py:55-70`
- Cleanup task: `core/cleanup.py:20-40`

**Job Queue:**
- Queue submission: `core/queue.py:25-40`
- Worker loop: `core/queue.py:60-100`

### Testing Locations

**Test Organization:**
- Unit tests: `tests/test_*.py`
- Integration tests: `tests/test_generation.py`
- Fixtures: `tests/fixtures/` (test images, audio)
- Pytest config: `tests/conftest.py`

**Test Commands:**
```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=api --cov=core --cov-report=html

# Run specific test file
pytest tests/test_api.py

# Run specific test
pytest tests/test_api.py::test_generate_endpoint_success

# Run with verbose output
pytest -v
```

### Documentation to Update

**After Story 1 (POC):**
- [ ] docs/DEPLOYMENT.md - RunPod deployment steps
- [ ] README.md - Add "Deployment" section

**After Story 2 (API):**
- [ ] docs/API.md - Endpoint documentation
- [ ] README.md - Add "API Usage" section with examples
- [ ] .env.example - Add all required env vars

**After Story 3 (Hardening):**
- [ ] docs/MONITORING.md - Monitoring setup guide
- [ ] docs/API.md - Add rate limiting details
- [ ] README.md - Add "Production Setup" section

---

## UX/UI Considerations

**No UI/UX impact - backend API only**

This is a headless API service. User experience considerations are limited to:

**API Developer Experience:**
- Clear, consistent endpoint naming
- Descriptive error messages with actionable guidance
- OpenAPI/Swagger documentation for easy exploration
- Example curl commands in documentation
- Reasonable timeouts and retry guidance

**Error Messages (Developer-Facing):**

Good error examples:
```json
{
  "error": {
    "code": "INVALID_IMAGE_FORMAT",
    "message": "Image must be PNG or JPEG format",
    "details": {
      "received_format": "gif",
      "supported_formats": ["png", "jpg", "jpeg"]
    }
  }
}
```

**Status Polling UX:**
- Return estimated completion time in status response
- Include progress percentage if possible
- Clear status values: "pending", "processing", "completed", "failed"

---

## Testing Approach

**Test Framework:** pytest 7.4.3 with pytest-asyncio 0.21.1

**Testing Strategy:**

**1. Unit Tests (Fast, Isolated):**
- Test API route handlers with mocked services
- Test Pydantic model validation
- Test storage client operations (mock boto3)
- Test queue operations (in-memory, no external deps)
- Test authentication middleware

**Example:**
```python
@pytest.mark.asyncio
async def test_generate_endpoint_requires_auth(client):
    response = await client.post("/generate")
    assert response.status_code == 401
    assert "error" in response.json()
```

**2. Integration Tests (Medium Speed):**
- Test full API flow with real queue but mocked InfiniteTalk
- Test R2 upload/download with test bucket
- Test cleanup job with test data

**Example:**
```python
@pytest.mark.asyncio
async def test_full_video_generation_flow(client, test_image, test_audio):
    # Submit job
    response = await client.post("/generate", files={...})
    job_id = response.json()["data"]["job_id"]

    # Poll status
    await asyncio.sleep(2)
    status = await client.get(f"/status/{job_id}")
    assert status.json()["data"]["status"] == "processing"

    # Get result (mocked generation completes immediately in tests)
    result = await client.get(f"/result/{job_id}")
    assert "url" in result.json()["data"]
```

**3. End-to-End Tests (Slow, Optional):**
- Deploy to RunPod staging environment
- Test actual video generation with real GPU
- Validate video quality and format
- Run manually before production deployment

**Coverage Requirements:**
- Overall coverage: 80%+ (measured by pytest-cov)
- Core business logic: 100% (infinitetalk.py, queue.py, storage.py)
- API routes: 90%+ (all endpoints, error cases)
- Skip coverage: InfiniteTalk library code (external dependency)

**Mocking Strategy:**
- Mock boto3 S3 client for storage tests
- Mock subprocess calls for InfiniteTalk in unit tests
- Use real in-memory queue (no mocking needed)
- Mock time.sleep in cleanup tests for speed

**Test Data:**
- Small test image: 512x512 PNG (~500KB)
- Short test audio: 5-10 second WAV (~1MB)
- Expected output: <50MB video for fast tests
- Store in `tests/fixtures/` directory

---

## Deployment Strategy

### Deployment Steps

**Initial Deployment (Story 1):**

1. **Build and Push Container:**
   ```bash
   docker build -t avatar-api:v1.0 .
   docker tag avatar-api:v1.0 yourdockerhub/avatar-api:v1.0
   docker push yourdockerhub/avatar-api:v1.0
   ```

2. **Configure RunPod:**
   - Navigate to RunPod Serverless console
   - Create new serverless endpoint
   - Select L40S GPU (48GB VRAM)
   - Point to Docker image: `yourdockerhub/avatar-api:v1.0`
   - Configure persistent volume: 50GB at `/runpod-volume`
   - Set environment variables (API_KEY, R2_*, HF_TOKEN, etc.)
   - Set scaling: Min=0, Max=5
   - Set timeout: 600 seconds

3. **First Startup (Model Download):**
   - Endpoint will auto-scale to 1 worker on first request
   - Models download automatically (~5-10 minutes)
   - Subsequent starts use cached models (<60s)

4. **Verify Deployment:**
   - Test health endpoint: `GET https://your-endpoint.runpod.io/health`
   - Submit test generation request
   - Verify video generated successfully

**Production Deployment (Story 2+):**

1. **Update Container:**
   ```bash
   docker build -t avatar-api:v1.1 .
   docker push yourdockerhub/avatar-api:v1.1
   ```

2. **Update RunPod Endpoint:**
   - Update image tag to v1.1
   - RunPod auto-deploys new version
   - Zero-downtime update (new requests use new version)

3. **Smoke Test:**
   - Run API tests against production endpoint
   - Verify no regressions

**CI/CD Pipeline (Story 3):**

GitHub Actions workflow:
```yaml
# .github/workflows/deploy.yml
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run tests
        run: |
          pip install -r requirements.txt
          pytest
      - name: Build and push Docker
        run: |
          docker build -t avatar-api:${{ github.sha }} .
          docker push yourdockerhub/avatar-api:${{ github.sha }}
      - name: Update RunPod endpoint
        run: |
          # Call RunPod API to update image tag
          curl -X POST https://api.runpod.io/v1/endpoints/update ...
```

### Rollback Plan

**If Issues Detected After Deployment:**

1. **Quick Rollback (RunPod Dashboard):**
   - Navigate to endpoint settings
   - Change image tag to previous version (e.g., v1.0)
   - Save changes (auto-deploys in ~30 seconds)

2. **Verify Rollback:**
   - Test health endpoint
   - Submit test generation request
   - Confirm previous functionality restored

3. **Investigate Issue:**
   - Check RunPod logs for errors
   - Review recent code changes
   - Fix issue in feature branch
   - Redeploy with fix

**Database Rollback (Story 3+):**
- If API key schema changed, run down migration
- Restore database backup if needed

### Monitoring

**Key Metrics to Track:**

1. **GPU Utilization:**
   - RunPod dashboard shows real-time GPU usage
   - Alert if utilization >90% for extended periods

2. **Generation Time:**
   - Log start/end time for each video generation
   - Track P50, P95, P99 latencies
   - Alert if P95 >180 seconds (3 minutes)

3. **Error Rate:**
   - Count failed generations vs successful
   - Alert if error rate >5%

4. **Cost Tracking:**
   - Daily GPU usage costs (RunPod billing)
   - Storage costs (R2 + RunPod volume)
   - Alert if daily cost >$5 (unexpected spike)

5. **API Metrics:**
   - Request count per endpoint
   - Response status code distribution
   - API key usage per key

**Monitoring Tools:**

**Story 1-2 (Basic):**
- RunPod dashboard (GPU, costs)
- Application logs (structured JSON to stdout)
- Manual cost review weekly

**Story 3 (Production):**
- Prometheus + Grafana (custom metrics)
- PagerDuty or similar for alerts
- Log aggregation (Loki, Datadog, or CloudWatch)
- Cost tracking dashboard

**Alerting Rules:**
- Critical: API down (health check fails)
- Warning: Error rate >5%
- Warning: Daily cost >$10
- Info: GPU utilization >80% (consider scaling up max workers)

---

**End of Technical Specification**

_This comprehensive tech-spec provides all the context needed for development. Proceed to Story 1 to begin implementation._
