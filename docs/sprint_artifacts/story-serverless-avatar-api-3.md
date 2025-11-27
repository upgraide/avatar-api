# Story 1.3: Production Hardening & Documentation

**Status:** Draft

---

## User Story

As a **product owner**,
I want **production-ready API with monitoring, enhanced security, and comprehensive documentation**,
So that **the service is maintainable, observable, ready for customer launch, and can scale safely**.

---

## Acceptance Criteria

**AC #1: Enhanced API Key Management**
- **Given** the API needs to support multiple customers
- **When** I implement database-backed API key storage
- **Then** API keys are stored securely (hashed)
- **And** each key can be associated with metadata (customer name, creation date)
- **And** keys can be revoked without code changes

**AC #2: Rate Limiting Prevents Abuse**
- **Given** each API key has usage limits
- **When** a client exceeds their rate limit (e.g., 10 requests/hour)
- **Then** subsequent requests return 429 Too Many Requests
- **And** the response includes retry-after header
- **And** rate limits reset after the time window

**AC #3: Monitoring Dashboard Shows Key Metrics**
- **Given** the API is running in production
- **When** I access the monitoring dashboard
- **Then** I can see:
  - GPU utilization over time
  - Request count per hour/day
  - Generation success/failure rate
  - Average generation time (P50, P95, P99)
  - Current cost tracking (daily/monthly)
- **And** metrics update in near real-time

**AC #4: Cost Alerts Configured**
- **Given** I want to prevent unexpected costs
- **When** daily GPU costs exceed threshold (e.g., $10)
- **Then** an alert is triggered (email or webhook)
- **And** I can review and adjust max workers or investigate

**AC #5: API Documentation Published**
- **Given** customers need to integrate the API
- **When** I navigate to the API documentation
- **Then** OpenAPI/Swagger UI is accessible at `/docs`
- **And** all endpoints are documented with request/response schemas
- **And** authentication requirements are clearly explained
- **And** example curl commands are provided

**AC #6: Deployment Guide Complete**
- **Given** someone needs to deploy or maintain the service
- **When** I review the deployment documentation
- **Then** docs/DEPLOYMENT.md covers:
  - Complete setup from scratch
  - Environment variable reference
  - Troubleshooting common issues
  - Update and rollback procedures
  - Monitoring setup

**AC #7: CI/CD Pipeline Runs Tests on PR**
- **Given** code changes are submitted
- **When** a pull request is created
- **Then** GitHub Actions workflow runs automatically
- **And** all tests execute (pytest)
- **And** PR status shows pass/fail
- **And** on merge to main, container builds and pushes to registry

---

## Implementation Details

### Tasks / Subtasks

#### Phase 1: Enhanced API Key Management (AC: #1)
- [ ] Design API key schema:
  ```python
  class APIKey:
      id: UUID
      key_hash: str  # SHA-256 hashed
      customer_name: str
      created_at: datetime
      revoked: bool
      rate_limit: int  # requests per hour
  ```
- [ ] Choose storage option:
  - [ ] Option A: SQLite database (simple, file-based)
  - [ ] Option B: PostgreSQL (more robust, requires separate service)
  - [ ] Recommendation: SQLite for MVP (embedded, no extra infra)
- [ ] Create `core/api_keys.py` - APIKeyManager class
  - [ ] Implement `create_key(customer_name, rate_limit)` method
  - [ ] Implement `verify_key(key)` method (hash and lookup)
  - [ ] Implement `revoke_key(key_id)` method
  - [ ] Implement `get_key_metadata(key)` method
- [ ] Create database migrations (if using SQLAlchemy)
- [ ] Update `api/middleware/auth.py`:
  - [ ] Replace env variable check with database lookup
  - [ ] Attach key metadata to request context
- [ ] Create admin utility script for key management:
  - [ ] `scripts/manage_keys.py` - CLI tool
  - [ ] Commands: create, list, revoke
- [ ] Migrate existing API_KEY from env to database (one-time)

#### Phase 2: Rate Limiting Implementation (AC: #2)
- [ ] Create `core/rate_limiter.py` - RateLimiter class
  - [ ] Use in-memory dict for tracking: `{key_id: {count, window_start}}`
  - [ ] Alternative: Redis for distributed rate limiting (future)
- [ ] Implement sliding window rate limiting:
  - [ ] Track request count per key per hour
  - [ ] Reset counter at window boundary
  - [ ] Return 429 when limit exceeded
- [ ] Create `api/middleware/rate_limit.py` - Rate limiting middleware
  - [ ] Check rate limit before processing request
  - [ ] Increment counter for valid requests
  - [ ] Add Retry-After header to 429 responses
  - [ ] Log rate limit violations
- [ ] Add rate_limit configuration per API key (from database)
- [ ] Test rate limiting:
  - [ ] Submit requests up to limit (should succeed)
  - [ ] Submit request over limit (should get 429)
  - [ ] Wait for window reset (should succeed again)

#### Phase 3: Monitoring Setup (AC: #3, #4)
- [ ] Choose monitoring approach:
  - [ ] Option A: Prometheus + Grafana (standard, powerful)
  - [ ] Option B: Simple logging + manual review (minimal)
  - [ ] Option C: Cloud service (Datadog, New Relic) (paid)
  - [ ] Recommendation: Start with enhanced logging + RunPod dashboard
- [ ] Add application metrics:
  - [ ] Create `core/metrics.py` - Metrics collector
  - [ ] Track: requests_total, requests_by_status, generation_duration_seconds
  - [ ] Track: queue_depth, active_jobs, gpu_utilization (from RunPod API)
  - [ ] Export metrics in Prometheus format (if using Prometheus)
- [ ] Create `/metrics` endpoint (Prometheus-compatible):
  - [ ] Expose collected metrics
  - [ ] Protected by API key or separate auth
- [ ] Set up cost tracking:
  - [ ] Query RunPod API for daily GPU usage
  - [ ] Calculate estimated cost: `seconds_used * $0.00019`
  - [ ] Log daily cost summary
- [ ] Configure alerts (AC: #4):
  - [ ] Create `core/alerts.py` - Alert manager
  - [ ] Implement alert rules (daily cost > $10, error rate > 5%)
  - [ ] Send alerts via email (SMTP) or webhook
  - [ ] Test alert triggering

#### Phase 4: Logging Improvements
- [ ] Enhance structured logging:
  - [ ] Add request_id to all log entries
  - [ ] Include customer_name from API key metadata
  - [ ] Log generation metrics (start time, duration, success/failure)
  - [ ] Log cost per request (GPU seconds used)
- [ ] Set up log aggregation (optional for MVP):
  - [ ] Option: Ship logs to CloudWatch, Loki, or Datadog
  - [ ] Retain logs for 30 days minimum
- [ ] Create log analysis helpers:
  - [ ] Script to parse logs and generate daily reports
  - [ ] Identify top customers by usage
  - [ ] Identify common error patterns

#### Phase 5: API Documentation (AC: #5)
- [ ] Ensure FastAPI OpenAPI is enabled (default)
- [ ] Customize OpenAPI schema in `api/main.py`:
  - [ ] Add title: "Avatar API"
  - [ ] Add description and version
  - [ ] Document authentication (Bearer token)
  - [ ] Add example responses for each endpoint
- [ ] Test Swagger UI at `/docs`:
  - [ ] Verify all endpoints visible
  - [ ] Verify schemas are clear
  - [ ] Test "Try it out" functionality
- [ ] Create `docs/API.md` with additional details:
  - [ ] Getting started guide
  - [ ] Authentication setup
  - [ ] Example curl commands:
    ```bash
    # Generate video
    curl -X POST https://your-endpoint.runpod.io/generate \
      -H "Authorization: Bearer your-api-key" \
      -F "image=@portrait.png" \
      -F "audio=@speech.wav" \
      -F "prompt=A woman singing"

    # Check status
    curl https://your-endpoint.runpod.io/status/{job_id} \
      -H "Authorization: Bearer your-api-key"

    # Get result
    curl https://your-endpoint.runpod.io/result/{job_id} \
      -H "Authorization: Bearer your-api-key"
    ```
  - [ ] Error code reference table
  - [ ] Rate limiting details
  - [ ] Best practices for integration

#### Phase 6: Deployment Documentation (AC: #6)
- [ ] Update `docs/DEPLOYMENT.md` with production sections:
  - [ ] Production checklist (security, scaling, backups)
  - [ ] Environment variables - complete reference
  - [ ] RunPod configuration - detailed settings
  - [ ] Monitoring setup instructions
  - [ ] Database initialization (API keys)
  - [ ] Troubleshooting guide:
    - [ ] Container won't start → check logs
    - [ ] Models won't download → verify HF token
    - [ ] API returns 500 → check env variables
    - [ ] Videos not uploading → check R2 credentials
    - [ ] High costs → review max workers setting
  - [ ] Update procedures:
    - [ ] Build new container version
    - [ ] Update RunPod endpoint image tag
    - [ ] Verify deployment with smoke tests
  - [ ] Rollback procedures:
    - [ ] Revert to previous image tag
    - [ ] Database rollback (if schema changed)
- [ ] Create runbook for common operations:
  - [ ] Creating new API keys
  - [ ] Revoking compromised keys
  - [ ] Investigating failed jobs
  - [ ] Scaling up/down max workers

#### Phase 7: CI/CD Pipeline (AC: #7)
- [ ] Create `.github/workflows/test.yml` - Test workflow
  - [ ] Trigger on: pull requests, push to main
  - [ ] Steps:
    - [ ] Checkout code
    - [ ] Set up Python 3.10
    - [ ] Install dependencies
    - [ ] Run pytest with coverage
    - [ ] Upload coverage report
    - [ ] Fail PR if tests fail or coverage <80%
- [ ] Create `.github/workflows/deploy.yml` - Deploy workflow
  - [ ] Trigger on: push to main (after tests pass)
  - [ ] Steps:
    - [ ] Checkout code
    - [ ] Build Docker image
    - [ ] Tag image with git SHA
    - [ ] Push to Docker Hub
    - [ ] (Optional) Update RunPod endpoint via API
    - [ ] Send deployment notification
- [ ] Configure GitHub secrets:
  - [ ] DOCKERHUB_USERNAME
  - [ ] DOCKERHUB_TOKEN
  - [ ] (Optional) RUNPOD_API_KEY for auto-deployment
- [ ] Test CI/CD pipeline:
  - [ ] Create test PR → verify tests run
  - [ ] Merge to main → verify build and push
  - [ ] Check RunPod endpoint updated (if auto-deploy)

#### Phase 8: Security Hardening
- [ ] Review security best practices:
  - [ ] API keys stored hashed, never in plaintext
  - [ ] Environment variables for secrets (never in code)
  - [ ] CORS configured to restrict origins
  - [ ] Input validation prevents injection attacks
  - [ ] Rate limiting prevents abuse
  - [ ] Logs don't contain sensitive data
- [ ] Add security headers middleware:
  - [ ] X-Content-Type-Options: nosniff
  - [ ] X-Frame-Options: DENY
  - [ ] Strict-Transport-Security (if HTTPS)
- [ ] Review and update `.gitignore`:
  - [ ] Ensure .env never committed
  - [ ] Exclude API key database
  - [ ] Exclude generated videos and temp files
- [ ] Create security documentation:
  - [ ] API key rotation policy
  - [ ] Incident response plan
  - [ ] Data retention policy (videos deleted after 6 hours)

#### Phase 9: Final Testing & Validation
- [ ] Run full test suite:
  - [ ] Unit tests pass
  - [ ] Integration tests pass
  - [ ] Coverage ≥80%
- [ ] Manual production testing:
  - [ ] Create API key via admin script
  - [ ] Submit video generation with new key
  - [ ] Verify rate limiting works
  - [ ] Trigger cost alert (lower threshold for test)
  - [ ] Review monitoring dashboard
  - [ ] Test key revocation
  - [ ] Test rollback procedure
- [ ] Load testing (optional):
  - [ ] Submit 10 concurrent requests
  - [ ] Verify all queue and complete successfully
  - [ ] Monitor GPU utilization
  - [ ] Confirm costs align with expectations

#### Phase 10: Launch Preparation
- [ ] Create customer onboarding checklist:
  - [ ] Provide API key
  - [ ] Share API documentation link
  - [ ] Set rate limits based on plan
  - [ ] Confirm integration working
- [ ] Set up on-call rotation (if applicable)
- [ ] Document escalation procedures
- [ ] Prepare launch announcement

### Technical Summary

**Objective:** Harden the production API with enhanced security (database-backed API keys, rate limiting), observability (monitoring, alerting), automation (CI/CD), and comprehensive documentation to ensure the service is maintainable and ready for customer launch.

**Key Technical Decisions:**

1. **API Key Storage:**
   - SQLite for MVP (embedded, simple, no extra infrastructure)
   - Keys stored hashed (SHA-256) for security
   - Metadata enables per-customer rate limits and tracking
   - Future: Migrate to PostgreSQL for high availability

2. **Rate Limiting Strategy:**
   - In-memory sliding window (MVP)
   - Per-key limits configurable in database
   - Returns 429 with Retry-After header
   - Future: Redis-based for distributed rate limiting

3. **Monitoring Approach:**
   - Enhanced structured logging (JSON format)
   - Application-level metrics (requests, duration, errors)
   - RunPod dashboard for GPU utilization
   - Cost tracking via RunPod API queries
   - Prometheus metrics endpoint (optional for MVP)

4. **CI/CD Pipeline:**
   - GitHub Actions for test automation
   - Build and push Docker on merge to main
   - Optional: Auto-update RunPod endpoint
   - Coverage gates prevent regressions

5. **Documentation Strategy:**
   - OpenAPI/Swagger UI at `/docs` (auto-generated)
   - Detailed API.md for customer integration
   - Comprehensive DEPLOYMENT.md for operations
   - Runbooks for common tasks

**Hardening Checklist:**
- ✅ API keys managed securely
- ✅ Rate limiting prevents abuse
- ✅ Monitoring provides visibility
- ✅ Alerts prevent cost overruns
- ✅ Documentation enables self-service
- ✅ CI/CD enables safe iteration
- ✅ Security best practices followed

**Files/Modules Involved:**
- `core/api_keys.py` - API key manager
- `core/rate_limiter.py` - Rate limiting logic
- `core/metrics.py` - Metrics collection
- `core/alerts.py` - Alert manager
- `api/middleware/rate_limit.py` - Rate limiting middleware
- `api/routes/metrics.py` - Metrics endpoint
- `scripts/manage_keys.py` - Admin CLI
- `.github/workflows/*.yml` - CI/CD pipelines
- `docs/API.md` - API documentation
- `docs/DEPLOYMENT.md` - Operations guide

### Project Structure Notes

- **Files to modify:**
  - `core/api_keys.py` - CREATE
  - `core/rate_limiter.py` - CREATE
  - `core/metrics.py` - CREATE
  - `core/alerts.py` - CREATE
  - `api/middleware/auth.py` - MODIFY (use database)
  - `api/middleware/rate_limit.py` - CREATE
  - `api/routes/metrics.py` - CREATE
  - `api/main.py` - MODIFY (add middleware, customize OpenAPI)
  - `scripts/manage_keys.py` - CREATE
  - `.github/workflows/test.yml` - CREATE
  - `.github/workflows/deploy.yml` - CREATE
  - `docs/API.md` - MODIFY (complete documentation)
  - `docs/DEPLOYMENT.md` - MODIFY (add production sections)
  - `README.md` - MODIFY (add badges, links to docs)
  - `requirements.txt` - MODIFY (add SQLAlchemy, prometheus-client)

- **Expected test locations:**
  - `tests/test_api_keys.py` - API key management tests
  - `tests/test_rate_limiter.py` - Rate limiting tests
  - `tests/test_metrics.py` - Metrics collection tests
  - Extend `tests/test_api.py` - Test rate limiting integration

- **Estimated effort:** 2 story points

- **Prerequisites:**
  - Story 1.1 complete (RunPod foundation)
  - Story 1.2 complete (functional API)
  - GitHub repository configured
  - Docker Hub account for CI/CD

### Key Code References

**SQLite with SQLAlchemy (Python ORM):**
- Connection: `sqlite:///api_keys.db`
- Schema definition using SQLAlchemy models
- Migrations: Alembic (optional) or manual SQL

**SHA-256 Hashing (API Keys):**
```python
import hashlib
key_hash = hashlib.sha256(api_key.encode()).hexdigest()
```

**Rate Limiting Algorithm:**
- Sliding window counter
- Track: `{key_id: {'count': N, 'window_start': timestamp}}`
- Reset when current_time > window_start + 3600

**Prometheus Metrics Format:**
```
# HELP requests_total Total API requests
# TYPE requests_total counter
requests_total{endpoint="/generate",status="200"} 42
```

**GitHub Actions Syntax:**
- Workflows in `.github/workflows/`
- Triggers: `on: [pull_request, push]`
- Jobs, steps, actions

---

## Context References

**Tech-Spec:** [tech-spec.md](../tech-spec.md) - Primary context document containing:

- Implementation Guide → Story 3 implementation steps (Production Hardening)
- Development Context → Configuration changes (env variables)
- Testing Approach → Coverage requirements
- Deployment Strategy → Monitoring approach, cost tracking

**Architecture:** Greenfield project - no existing architecture docs

**Research:** [research-technical-2025-11-26.md](../research-technical-2025-11-26.md):
- Section 7: Implementation Roadmap → Week 3 Hardening details
- Section 9: Recommendations → Risk mitigation strategies

**Previous Stories:**
- Story 1.1 - RunPod Foundation (provides infrastructure)
- Story 1.2 - Production API (provides functional API to harden)

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
