# Story 1.2: Production API Development

**Status:** Draft

---

## User Story

As an **API consumer**,
I want **a REST API to submit image + audio and receive generated talking avatar videos**,
So that **I can integrate infinite-length avatar generation into my application with simple HTTP requests**.

---

## Acceptance Criteria

**AC #1: Generate Endpoint Accepts Requests**
- **Given** I have a valid API key
- **When** I POST to `/generate` with image file, audio file, and prompt
- **Then** the request is accepted (200 OK)
- **And** a unique job_id is returned immediately
- **And** the request validates input formats and sizes

**AC #2: API Key Authentication Works**
- **Given** the API is deployed
- **When** I send a request without an API key
- **Then** I receive 401 Unauthorized response
- **And** when I send a request with an invalid API key
- **Then** I receive 401 Unauthorized response
- **And** when I send a request with a valid API key
- **Then** the request is processed successfully

**AC #3: Job Status Endpoint Returns Progress**
- **Given** I have submitted a job with job_id
- **When** I GET `/status/{job_id}`
- **Then** I receive the current job status: "pending", "processing", "completed", or "failed"
- **And** the response includes timestamp and progress information
- **And** for completed jobs, the response includes result URL

**AC #4: Result Endpoint Returns Video URL**
- **Given** a job has completed successfully
- **When** I GET `/result/{job_id}`
- **Then** I receive a presigned R2 URL to download the video
- **And** the URL is valid for 6 hours
- **And** the video is downloadable and playable (720p MP4)

**AC #5: Videos Upload to R2 Successfully**
- **Given** InfiniteTalk generates a video
- **When** the video generation completes
- **Then** the video is uploaded to Cloudflare R2
- **And** a presigned URL is generated with 6-hour expiry
- **And** the local temp video file is deleted

**AC #6: Videos Auto-Delete After 6 Hours**
- **Given** videos are uploaded to R2
- **When** the cleanup task runs periodically
- **Then** videos older than 6 hours are deleted from R2
- **And** storage costs remain minimal

**AC #7: Concurrent Requests Queue Properly**
- **Given** multiple video generation requests arrive simultaneously
- **When** the job queue processes them
- **Then** requests are handled sequentially (one GPU job at a time)
- **And** all jobs complete successfully without errors
- **And** status endpoints return accurate progress for each job

**AC #8: Errors Return Structured JSON**
- **Given** various error scenarios occur
- **When** I make API requests
- **Then** all errors return consistent JSON format:
  ```json
  {
    "error": {
      "code": "ERROR_CODE",
      "message": "Human-readable message",
      "details": {}
    }
  }
  ```
- **And** appropriate HTTP status codes are used (400, 401, 500, etc.)

**AC #9: API Tests Pass with 80%+ Coverage**
- **Given** the API implementation is complete
- **When** I run `pytest --cov`
- **Then** all tests pass
- **And** code coverage is ≥80% for API and core modules
- **And** critical paths have 100% coverage

**AC #10: Production Deployment Functions**
- **Given** the API code is complete
- **When** I deploy the updated container to RunPod
- **Then** the API is accessible at the RunPod endpoint URL
- **And** all endpoints respond correctly
- **And** video generation works end-to-end

---

## Implementation Details

### Tasks / Subtasks

#### Phase 1: FastAPI Application Setup (AC: #1, #2)
- [ ] Create `api/main.py` - FastAPI application entry point
  - [ ] Initialize FastAPI app with CORS middleware
  - [ ] Add structured logging middleware
  - [ ] Configure exception handlers for consistent error responses
- [ ] Create `api/middleware/auth.py` - API key authentication (AC: #2)
  - [ ] Implement `verify_api_key()` dependency
  - [ ] Check Authorization header for Bearer token
  - [ ] Return 401 if missing or invalid
  - [ ] Load API key from environment variable initially
- [ ] Create `api/models/requests.py` - Pydantic request models
  - [ ] `GenerateRequest` model (prompt: str)
  - [ ] File validation for image (PNG/JPG, max 10MB)
  - [ ] File validation for audio (WAV/MP3, max 50MB)
- [ ] Create `api/models/responses.py` - Pydantic response models
  - [ ] `JobResponse` (job_id, status, created_at)
  - [ ] `StatusResponse` (job_id, status, progress, result_url)
  - [ ] `ErrorResponse` (code, message, details)

#### Phase 2: API Route Handlers (AC: #1, #3, #4)
- [ ] Create `api/routes/generate.py` - POST /generate endpoint (AC: #1)
  - [ ] Accept multipart form data (image, audio, prompt)
  - [ ] Validate inputs using Pydantic models
  - [ ] Generate unique job_id (UUID4)
  - [ ] Save uploaded files to temp storage
  - [ ] Submit job to queue
  - [ ] Return 200 with job_id immediately
- [ ] Create `api/routes/status.py` - GET /status/{job_id} (AC: #3)
  - [ ] Look up job in queue status dict
  - [ ] Return current status and progress
  - [ ] Include result_url if completed
  - [ ] Return 404 if job_id not found
- [ ] Create `api/routes/result.py` - GET /result/{job_id} (AC: #4)
  - [ ] Check job status is "completed"
  - [ ] Return presigned R2 URL from storage service
  - [ ] Return 404 if job not found or not completed
  - [ ] Return 500 if URL generation fails
- [ ] Create `api/routes/health.py` - GET /health endpoint
  - [ ] Return basic health check (200 OK)
  - [ ] Include service status and version

#### Phase 3: Background Job Queue (AC: #7)
- [ ] Create `core/queue.py` - JobQueue class
  - [ ] Initialize asyncio.Queue for job submissions
  - [ ] Maintain status dict: `{job_id: {status, progress, result_url, error}}`
  - [ ] Implement `submit_job(job_id, image_path, audio_path, prompt)` method
  - [ ] Implement `get_status(job_id)` method
  - [ ] Implement `update_status(job_id, status, **kwargs)` method
- [ ] Create async worker loop:
  - [ ] Process jobs from queue sequentially
  - [ ] Update status to "processing"
  - [ ] Call InfiniteTalk service
  - [ ] Upload result to R2
  - [ ] Update status to "completed" with result URL
  - [ ] Handle errors and update status to "failed"
- [ ] Start worker loop on application startup

#### Phase 4: InfiniteTalk Wrapper (AC: #1, #7)
- [ ] Create `core/infinitetalk.py` - InfiniteTalkService class
  - [ ] Implement `generate_video(image_path, audio_path, prompt)` method
  - [ ] Create input JSON for InfiniteTalk
  - [ ] Call generate_infinitetalk.py via subprocess:
    ```python
    subprocess.run([
        "python", "InfiniteTalk/generate_infinitetalk.py",
        "--task", "infinitetalk-14B",
        "--size", "infinitetalk-720",
        "--ckpt_dir", "/runpod-volume/models/Wan2.1-I2V-14B-480P",
        "--infinitetalk_dir", "/runpod-volume/models/InfiniteTalk",
        "--wav2vec_dir", "/runpod-volume/models/chinese-wav2vec2-base",
        "--num_persistent_param_in_dit", "0",
        "--input_json", input_json_path,
        "--save_file", output_path
    ])
    ```
  - [ ] Monitor subprocess output for errors
  - [ ] Return path to generated video
  - [ ] Clean up temp input files
  - [ ] Raise exception on subprocess failure

#### Phase 5: R2 Storage Integration (AC: #5, #6)
- [ ] Create `core/storage.py` - R2StorageService class
  - [ ] Initialize boto3 S3 client with R2 endpoint
  - [ ] Load R2 credentials from environment variables
- [ ] Implement `upload_video(file_path, job_id)` method (AC: #5)
  - [ ] Upload to R2: `videos/{job_id}.mp4`
  - [ ] Return S3 object key
  - [ ] Retry 3 times with exponential backoff on failure
- [ ] Implement `generate_presigned_url(job_id, expiry=21600)` method
  - [ ] Generate presigned GET URL (6 hours = 21600 seconds)
  - [ ] Return accessible HTTPS URL
- [ ] Create `core/cleanup.py` - Scheduled cleanup task (AC: #6)
  - [ ] Implement `cleanup_old_videos()` function
  - [ ] List all objects in R2 bucket
  - [ ] Filter videos older than 6 hours (based on upload timestamp)
  - [ ] Delete old videos
  - [ ] Log deletion count
- [ ] Schedule cleanup task to run every hour (asyncio background task)

#### Phase 6: Error Handling & Logging (AC: #8)
- [ ] Create custom exception classes in `api/exceptions.py`:
  - [ ] `InvalidInputError` (400)
  - [ ] `UnauthorizedError` (401)
  - [ ] `NotFoundError` (404)
  - [ ] `GenerationError` (500)
  - [ ] `StorageError` (500)
- [ ] Add FastAPI exception handlers in `api/main.py`
  - [ ] Handle custom exceptions → structured JSON response
  - [ ] Handle validation errors → 400 with details
  - [ ] Handle unexpected errors → 500 with generic message (log details)
- [ ] Configure structured logging (JSON format):
  - [ ] Log all requests (method, path, status, duration)
  - [ ] Log job submissions and completions
  - [ ] Log errors with full traceback
  - [ ] Never log sensitive data (API keys)

#### Phase 7: Configuration Management
- [ ] Create `config.py` - Centralized configuration
  - [ ] Load all settings from environment variables
  - [ ] Validate required variables on startup
  - [ ] Provide sensible defaults where possible
- [ ] Update `.env.example` with all required variables:
  ```
  API_KEY=your-secret-api-key
  R2_ACCOUNT_ID=your-r2-account-id
  R2_ACCESS_KEY_ID=your-r2-access-key
  R2_SECRET_ACCESS_KEY=your-r2-secret
  R2_BUCKET_NAME=avatar-videos
  MODEL_STORAGE_PATH=/runpod-volume/models
  VIDEO_RETENTION_HOURS=6
  LOG_LEVEL=INFO
  ```

#### Phase 8: Testing (AC: #9)
- [ ] Create `tests/conftest.py` - Pytest fixtures
  - [ ] `client` fixture - TestClient for FastAPI
  - [ ] `auth_headers` fixture - Valid API key headers
  - [ ] `test_image` fixture - Small test image file
  - [ ] `test_audio` fixture - Short test audio file
  - [ ] `mock_infinitetalk` fixture - Mock video generation
  - [ ] `mock_r2` fixture - Mock R2 client
- [ ] Create `tests/test_api.py` - API endpoint tests
  - [ ] Test POST /generate requires auth (401 without key)
  - [ ] Test POST /generate accepts valid request (200)
  - [ ] Test POST /generate validates image format (400 for invalid)
  - [ ] Test POST /generate validates file size (413 for too large)
  - [ ] Test GET /status returns pending/processing/completed
  - [ ] Test GET /status returns 404 for unknown job_id
  - [ ] Test GET /result returns presigned URL for completed job
  - [ ] Test GET /result returns 404 for incomplete job
  - [ ] Test GET /health returns 200
- [ ] Create `tests/test_generation.py` - Integration tests
  - [ ] Test full flow: submit → status → result (with mocked InfiniteTalk)
  - [ ] Test concurrent requests queue properly
  - [ ] Test error handling (generation failure)
- [ ] Create `tests/test_storage.py` - R2 storage tests
  - [ ] Test upload_video success
  - [ ] Test upload_video retry on failure
  - [ ] Test generate_presigned_url
  - [ ] Test cleanup_old_videos deletes only old files
- [ ] Run tests with coverage: `pytest --cov=api --cov=core --cov-report=html`
- [ ] Ensure ≥80% coverage

#### Phase 9: Production Deployment (AC: #10)
- [ ] Update Dockerfile to include API code:
  - [ ] Copy `api/` and `core/` directories
  - [ ] Install FastAPI dependencies
  - [ ] Change CMD to start uvicorn server
- [ ] Build and push updated container: `avatar-api:v1.1`
- [ ] Update RunPod endpoint to use new image
- [ ] Set all environment variables in RunPod dashboard
- [ ] Test deployment:
  - [ ] Call /health endpoint (verify 200 OK)
  - [ ] Submit test generation request
  - [ ] Poll status until completed
  - [ ] Download video from presigned URL
  - [ ] Verify video quality

#### Phase 10: Documentation
- [ ] Update README.md with API usage examples:
  - [ ] curl commands for each endpoint
  - [ ] Example request/response payloads
  - [ ] Authentication instructions
- [ ] Create `docs/API.md` - Detailed API documentation
  - [ ] Endpoint reference (path, method, parameters)
  - [ ] Request/response schemas
  - [ ] Error code reference
  - [ ] Rate limiting info (for Story 1.3)

### Technical Summary

**Objective:** Build a production-ready FastAPI REST API that wraps InfiniteTalk video generation, handles async job processing, stores videos in R2, and provides clean HTTP endpoints for client integration.

**Key Technical Decisions:**

1. **FastAPI Framework:**
   - Modern async Python framework
   - Automatic OpenAPI documentation
   - Built-in request validation via Pydantic
   - Fast performance with async/await

2. **In-Memory Job Queue (MVP):**
   - `asyncio.Queue` for job submissions
   - Simple dict for status tracking
   - Sequential processing (one GPU job at a time)
   - Trade-off: Not persistent across restarts (acceptable for MVP)
   - Future: Migrate to Redis for persistence

3. **Cloudflare R2 Storage:**
   - S3-compatible API (use boto3)
   - No egress fees (cost savings vs AWS S3)
   - Presigned URLs for secure downloads
   - 6-hour retention with automated cleanup

4. **Basic Authentication (MVP):**
   - Single API key from environment variable
   - Bearer token in Authorization header
   - Simple but secure for launch
   - Future: Database-backed keys in Story 1.3

5. **Async Architecture:**
   - FastAPI endpoints return immediately
   - Background worker processes jobs asynchronously
   - Client polls /status for progress
   - Scales to multiple concurrent submissions

**Architecture Flow:**
```
Client Request
    ↓
POST /generate (validate, create job_id, return immediately)
    ↓
Job Queue (asyncio.Queue)
    ↓
Async Worker Loop (one at a time)
    ↓
InfiniteTalk Wrapper (subprocess)
    ↓
Generated Video → Upload to R2
    ↓
Presigned URL → Update job status
    ↓
Client polls GET /status → GET /result
```

**Files/Modules Involved:**
- `api/main.py` - FastAPI app
- `api/routes/*.py` - Endpoint handlers
- `api/models/*.py` - Pydantic schemas
- `api/middleware/auth.py` - Authentication
- `core/infinitetalk.py` - Video generation wrapper
- `core/storage.py` - R2 client
- `core/queue.py` - Job queue manager
- `core/cleanup.py` - Scheduled cleanup
- `tests/*.py` - Test suite

### Project Structure Notes

- **Files to modify:**
  - `api/main.py` - CREATE
  - `api/routes/generate.py` - CREATE
  - `api/routes/status.py` - CREATE
  - `api/routes/result.py` - CREATE
  - `api/routes/health.py` - CREATE
  - `api/models/requests.py` - CREATE
  - `api/models/responses.py` - CREATE
  - `api/middleware/auth.py` - CREATE
  - `api/middleware/logging.py` - CREATE
  - `api/exceptions.py` - CREATE
  - `core/infinitetalk.py` - CREATE
  - `core/storage.py` - CREATE
  - `core/queue.py` - CREATE
  - `core/cleanup.py` - CREATE
  - `config.py` - CREATE
  - `requirements.txt` - MODIFY (add FastAPI, boto3, etc.)
  - `Dockerfile` - MODIFY (copy API code, change CMD)
  - `.env.example` - MODIFY (add R2 variables)
  - `tests/conftest.py` - CREATE
  - `tests/test_api.py` - CREATE
  - `tests/test_generation.py` - CREATE
  - `tests/test_storage.py` - CREATE
  - `README.md` - MODIFY (add API usage section)
  - `docs/API.md` - CREATE

- **Expected test locations:**
  - `tests/test_api.py` - API endpoint unit tests
  - `tests/test_generation.py` - Integration tests
  - `tests/test_storage.py` - R2 storage tests
  - `tests/fixtures/` - Test image and audio files

- **Estimated effort:** 5 story points

- **Prerequisites:**
  - Story 1.1 complete (working RunPod deployment with models)
  - Cloudflare R2 bucket created and configured
  - R2 access keys generated
  - API key generated (secure random string)

### Key Code References

**FastAPI Application Pattern:**
- Reference tech-spec.md → Technical Approach → API Design (RESTful, async/await)
- FastAPI docs: https://fastapi.tiangolo.com/

**InfiniteTalk Subprocess Call:**
- From Story 1.1: InfiniteTalk/generate_infinitetalk.py command structure
- Key args: --task, --size, --ckpt_dir, --num_persistent_param_in_dit

**R2 (S3-Compatible) Client:**
- boto3 S3 client with custom endpoint_url
- Operations: put_object, generate_presigned_url, delete_object
- Example endpoint: `https://<account-id>.r2.cloudflarestorage.com`

**Pydantic Validation:**
- File upload validation: file.content_type, file.size
- Custom validators for image/audio formats
- Error messages for invalid inputs

---

## Context References

**Tech-Spec:** [tech-spec.md](../tech-spec.md) - Primary context document containing:

- Implementation Details → Source Tree Changes (all API files to create)
- Implementation Details → Technical Approach (API design, job queue, storage)
- Implementation Guide → Story 2 implementation steps (Days 4-8)
- Development Context → Framework dependencies (FastAPI 0.104.1, boto3, etc.)
- Development Context → Configuration changes (.env variables)
- Developer Resources → File paths and testing locations
- Testing Approach → Test framework and coverage requirements

**Architecture:** Greenfield project - no existing architecture docs

**Research:** [research-technical-2025-11-26.md](../research-technical-2025-11-26.md):
- Section 7: Implementation Roadmap → Week 2 API Development details
- Section 5: InfiniteTalk Repository Analysis → Input/Output contract
- Section 9: Recommendations → Cloudflare R2 storage recommendation

**Previous Story:**
- Story 1.1 - RunPod Foundation & Model Setup (MUST be complete before starting)

---

## Dev Agent Record

### Agent Model Used

<!-- Will be populated during dev-story execution -->

### Debug Log References

<!-- Will be populated during dev-story execution -->

### Completion Notes

<!-- Will be populated during dev-story execution -->

### Files Modified

<!-- Will be populated during dev-story execution -->

### Test Results

<!-- Will be populated during dev-story execution -->

---

## Review Notes

<!-- Will be populated during code review -->
