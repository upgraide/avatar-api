"""
Avatar API - FastAPI wrapper for InfiniteTalk video generation

Endpoints:
- POST /generate - Generate talking avatar video from image + audio
- GET /health - Health check endpoint
"""

import os
import json
import uuid
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Depends, Header
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# Configuration from environment
API_KEY = os.getenv("API_KEY", "")
MODEL_STORAGE_PATH = os.getenv("MODEL_STORAGE_PATH", "/workspace/models")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/tmp/avatar-outputs")

# Model paths
CKPT_DIR = os.path.join(MODEL_STORAGE_PATH, "Wan2.1-I2V-14B-480P")
WAV2VEC_DIR = os.path.join(MODEL_STORAGE_PATH, "chinese-wav2vec2-base")
INFINITETALK_DIR = os.path.join(MODEL_STORAGE_PATH, "InfiniteTalk")

app = FastAPI(
    title="Avatar API",
    description="Generate talking avatar videos from image + audio",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def verify_api_key(authorization: Optional[str] = Header(None)):
    """Verify API key from Authorization header."""
    if not API_KEY:
        # No API key configured - allow all requests (dev mode)
        return True

    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    # Support both "Bearer <key>" and raw key
    token = authorization.replace("Bearer ", "").strip()

    if token != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")

    return True


def verify_models():
    """Check if all required models are available."""
    required_paths = [
        (CKPT_DIR, "Wan2.1-I2V-14B-480P"),
        (WAV2VEC_DIR, "chinese-wav2vec2-base"),
        (INFINITETALK_DIR, "InfiniteTalk"),
    ]

    missing = []
    for path, name in required_paths:
        if not os.path.exists(path):
            missing.append(name)

    return missing


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    missing_models = verify_models()

    if missing_models:
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": "Missing models",
                "missing": missing_models,
                "model_path": MODEL_STORAGE_PATH
            }
        )

    return {
        "status": "healthy",
        "model_path": MODEL_STORAGE_PATH,
        "models": {
            "wan2.1": os.path.exists(CKPT_DIR),
            "wav2vec2": os.path.exists(WAV2VEC_DIR),
            "infinitetalk": os.path.exists(INFINITETALK_DIR)
        }
    }


@app.post("/generate")
async def generate_video(
    image: UploadFile = File(..., description="Reference image (PNG/JPG)"),
    audio: UploadFile = File(..., description="Audio file (WAV/MP3)"),
    prompt: str = Form(
        default="A person speaking naturally",
        description="Description of the scene"
    ),
    size: str = Form(
        default="infinitetalk-720",
        description="Output size: infinitetalk-480 or infinitetalk-720"
    ),
    sample_steps: int = Form(
        default=40,
        description="Number of sampling steps (20-50)"
    ),
    _: bool = Depends(verify_api_key)
):
    """
    Generate a talking avatar video from an image and audio file.

    - **image**: Reference portrait image (PNG or JPG)
    - **audio**: Audio file for lip-sync (WAV or MP3)
    - **prompt**: Description of the scene/person
    - **size**: Output resolution (infinitetalk-480 or infinitetalk-720)
    - **sample_steps**: Quality vs speed tradeoff (20=fast, 40=balanced, 50=best)

    Returns the generated video file.
    """
    # Validate models exist
    missing_models = verify_models()
    if missing_models:
        raise HTTPException(
            status_code=503,
            detail=f"Models not available: {missing_models}. Check MODEL_STORAGE_PATH={MODEL_STORAGE_PATH}"
        )

    # Validate inputs
    if size not in ["infinitetalk-480", "infinitetalk-720"]:
        raise HTTPException(status_code=400, detail="size must be infinitetalk-480 or infinitetalk-720")

    if not 10 <= sample_steps <= 100:
        raise HTTPException(status_code=400, detail="sample_steps must be between 10 and 100")

    # Create job directory
    job_id = str(uuid.uuid4())[:8]
    job_dir = Path(OUTPUT_DIR) / job_id
    job_dir.mkdir(parents=True, exist_ok=True)

    try:
        # Save uploaded files
        image_path = job_dir / f"input_image{Path(image.filename).suffix}"
        audio_path = job_dir / f"input_audio{Path(audio.filename).suffix}"

        with open(image_path, "wb") as f:
            shutil.copyfileobj(image.file, f)

        with open(audio_path, "wb") as f:
            shutil.copyfileobj(audio.file, f)

        # Create input JSON for InfiniteTalk
        input_json = {
            "prompt": prompt,
            "cond_video": str(image_path),
            "cond_audio": {
                "person1": str(audio_path)
            }
        }

        input_json_path = job_dir / "input.json"
        with open(input_json_path, "w") as f:
            json.dump(input_json, f, indent=2)

        # Output path (InfiniteTalk adds .mp4 extension)
        output_base = job_dir / "output"
        output_video = job_dir / "output.mp4"

        # Build InfiniteTalk command
        cmd = [
            "python", "/app/InfiniteTalk/generate_infinitetalk.py",
            "--task", "infinitetalk-14B",
            "--size", size,
            "--ckpt_dir", CKPT_DIR,
            "--infinitetalk_dir", INFINITETALK_DIR,
            "--wav2vec_dir", WAV2VEC_DIR,
            "--input_json", str(input_json_path),
            "--sample_steps", str(sample_steps),
            "--mode", "streaming",
            "--save_file", str(output_base)
        ]

        print(f"[{job_id}] Starting generation...")
        print(f"[{job_id}] Command: {' '.join(cmd)}")

        # Run InfiniteTalk
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )

        if result.returncode != 0:
            print(f"[{job_id}] Generation failed:")
            print(f"[{job_id}] stdout: {result.stdout}")
            print(f"[{job_id}] stderr: {result.stderr}")
            raise HTTPException(
                status_code=500,
                detail=f"Video generation failed: {result.stderr[-500:] if result.stderr else 'Unknown error'}"
            )

        # Check output exists
        if not output_video.exists():
            # Try alternate output patterns
            mp4_files = list(job_dir.glob("*.mp4"))
            if mp4_files:
                output_video = mp4_files[0]
            else:
                raise HTTPException(
                    status_code=500,
                    detail="Video generation completed but output file not found"
                )

        print(f"[{job_id}] Generation complete: {output_video}")

        # Return video file
        return FileResponse(
            path=str(output_video),
            media_type="video/mp4",
            filename=f"avatar_{job_id}.mp4",
            headers={
                "X-Job-ID": job_id
            }
        )

    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Video generation timed out (>10 minutes)")

    except HTTPException:
        raise

    except Exception as e:
        print(f"[{job_id}] Unexpected error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        # Cleanup is handled by caller or scheduled task
        # For now, keep files for debugging
        pass


@app.get("/")
async def root():
    """Root endpoint with API info."""
    return {
        "name": "Avatar API",
        "version": "1.0.0",
        "endpoints": {
            "POST /generate": "Generate talking avatar video",
            "GET /health": "Health check",
        },
        "docs": "/docs"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
