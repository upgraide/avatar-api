"""
Model Manager for Avatar API
Verifies InfiniteTalk models embedded in Docker image are accessible.
Models are baked into the image at /app/models/ during Docker build.
"""

import os
import sys
import time
import logging
from pathlib import Path
from typing import Dict, Optional
from huggingface_hub import snapshot_download, hf_hub_download

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)


class ModelManager:
    """
    Manages verification of ML models for InfiniteTalk.

    Models are embedded in Docker image at /app/models/ during build.
    This class verifies models exist and are accessible at runtime.
    """

    # Model configurations
    # Models embedded in Docker image at: /app/models/{local_dir}/
    MODELS = {
        "wan2.1-i2v-14b": {
            "repo_id": "Wan-AI/Wan2.1-I2V-14B-480P",
            "local_dir": "Wan2.1-I2V-14B-480P",
            "size_gb": 77,  # Actual size: 77GB (7 shards + encoders)
            "description": "Wan 2.1 Image-to-Video 14B model"
        },
        "chinese-wav2vec2": {
            "repo_id": "TencentGameMate/chinese-wav2vec2-base",
            "local_dir": "chinese-wav2vec2-base",
            "size_gb": 1.5,
            "description": "Chinese Wav2Vec2 audio encoder"
        },
        "infinitetalk": {
            "repo_id": "MeiGen-AI/InfiniteTalk",
            "local_dir": "InfiniteTalk",
            "size_gb": 158,  # Actual size: 158GB (includes quantized variants)
            "description": "InfiniteTalk weights and audio conditioning"
        }
    }

    def __init__(self, storage_path: str = "/app/models"):
        """
        Initialize ModelManager.

        Args:
            storage_path: Path to embedded models directory (default: /app/models)

        Note: Models are embedded in Docker image during build.
              This manager verifies they exist and are accessible.
        """
        self.storage_path = Path(storage_path)
        self.hf_token = os.getenv("HF_TOKEN")  # Not used, but kept for compatibility

        logger.info(f"ModelManager initialized with embedded models path: {self.storage_path}")
        logger.info("Models embedded in Docker image - verifying accessibility...")

    def is_model_downloaded(self, model_key: str) -> bool:
        """
        Check if a model is already downloaded.

        Args:
            model_key: Key from MODELS dict (e.g., "wan2.1-i2v-14b")

        Returns:
            True if model exists in storage, False otherwise
        """
        if model_key not in self.MODELS:
            raise ValueError(f"Unknown model: {model_key}")

        model_config = self.MODELS[model_key]
        model_path = self.storage_path / model_config["local_dir"]

        # Check if directory exists and contains files
        if model_path.exists() and list(model_path.iterdir()):
            logger.info(f"✓ Model '{model_key}' already exists at {model_path}")
            return True

        logger.info(f"✗ Model '{model_key}' not found at {model_path}")
        return False

    def download_model(self, model_key: str, max_retries: int = 3) -> Path:
        """
        Download a model from Hugging Face to persistent storage.

        Args:
            model_key: Key from MODELS dict
            max_retries: Maximum number of download attempts

        Returns:
            Path to downloaded model directory

        Raises:
            Exception: If download fails after max_retries
        """
        if model_key not in self.MODELS:
            raise ValueError(f"Unknown model: {model_key}")

        model_config = self.MODELS[model_key]
        local_path = self.storage_path / model_config["local_dir"]

        logger.info(f"Downloading '{model_key}' ({model_config['description']})")
        logger.info(f"  Repo: {model_config['repo_id']}")
        logger.info(f"  Size: ~{model_config['size_gb']}GB")
        logger.info(f"  Destination: {local_path}")

        for attempt in range(1, max_retries + 1):
            try:
                logger.info(f"  Attempt {attempt}/{max_retries}...")

                start_time = time.time()

                # Download using Hugging Face Hub
                snapshot_download(
                    repo_id=model_config["repo_id"],
                    local_dir=str(local_path),
                    token=self.hf_token,
                    resume_download=True,
                    max_workers=4
                )

                elapsed = time.time() - start_time
                logger.info(f"✓ Downloaded '{model_key}' in {elapsed:.1f}s")

                return local_path

            except Exception as e:
                logger.error(f"✗ Download attempt {attempt} failed: {e}")

                if attempt < max_retries:
                    wait_time = 2 ** attempt  # Exponential backoff
                    logger.info(f"  Retrying in {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    raise Exception(f"Failed to download '{model_key}' after {max_retries} attempts")

        return local_path

    def ensure_models_downloaded(self) -> Dict[str, Path]:
        """
        Ensure all required models are downloaded.

        Downloads any missing models. Skips models that already exist.

        Returns:
            Dict mapping model keys to their local paths

        Raises:
            Exception: If any model download fails
        """
        logger.info("="*60)
        logger.info("CHECKING MODEL AVAILABILITY")
        logger.info("="*60)

        model_paths = {}
        download_required = []

        # Check which models need downloading
        for model_key in self.MODELS.keys():
            if self.is_model_downloaded(model_key):
                model_config = self.MODELS[model_key]
                model_paths[model_key] = self.storage_path / model_config["local_dir"]
            else:
                download_required.append(model_key)

        # Download missing models
        if download_required:
            logger.info(f"\n{len(download_required)} model(s) need downloading...")
            total_size = sum(self.MODELS[k]["size_gb"] for k in download_required)
            logger.info(f"Total download size: ~{total_size}GB")
            logger.info("This may take 5-10 minutes on first startup.\n")

            for model_key in download_required:
                model_paths[model_key] = self.download_model(model_key)
        else:
            logger.info("\n✓ All models already downloaded! Skipping download phase.")

        logger.info("\n" + "="*60)
        logger.info("MODEL CHECK COMPLETE")
        logger.info("="*60)

        return model_paths

    def verify_models(self) -> Dict[str, Path]:
        """
        Verify all required models exist in embedded storage.

        This is a runtime check that verifies models were properly embedded
        in the Docker image during build.

        Returns:
            Dict mapping model keys to their local paths

        Raises:
            RuntimeError: If any required model is missing
        """
        logger.info("="*60)
        logger.info("VERIFYING EMBEDDED MODELS")
        logger.info("="*60)

        model_paths = {}
        missing_models = []

        # Check each model
        for model_key, config in self.MODELS.items():
            model_path = self.storage_path / config["local_dir"]

            # Check if directory exists and has files
            if model_path.exists() and any(model_path.iterdir()):
                file_count = len(list(model_path.iterdir()))
                logger.info(f"✓ {config['description']}: {file_count} files at {model_path}")
                model_paths[model_key] = model_path
            else:
                logger.error(f"✗ {config['description']}: NOT FOUND at {model_path}")
                missing_models.append((model_key, config))

        if missing_models:
            logger.error("\n" + "="*60)
            logger.error("MODELS MISSING - DOCKER IMAGE NOT BUILT CORRECTLY")
            logger.error("="*60)
            logger.error(f"\nMissing {len(missing_models)} model(s):")
            for model_key, config in missing_models:
                logger.error(f"  - {config['description']} ({config['repo_id']})")
            logger.error("\nThis indicates the Docker image was not built properly.")
            logger.error("Models should be embedded during Docker build with:")
            logger.error("  docker build --build-arg HF_TOKEN=your_token -t avatar-api:v1.0 .")
            logger.error("\nExpected model paths in image:")
            for model_key, config in missing_models:
                logger.error(f"  /app/models/{config['local_dir']}/")
            logger.error("\nSee docs/DEPLOYMENT.md for detailed build instructions")
            raise RuntimeError(f"{len(missing_models)} required model(s) not found in Docker image")

        logger.info("\n" + "="*60)
        logger.info("✅ ALL MODELS EMBEDDED AND ACCESSIBLE")
        logger.info("="*60)

        return model_paths

    def get_model_paths(self) -> Dict[str, Path]:
        """
        Get paths to all models (assumes they are already downloaded).

        Returns:
            Dict mapping model keys to their local paths
        """
        return {
            model_key: self.storage_path / config["local_dir"]
            for model_key, config in self.MODELS.items()
        }


def main():
    """
    CLI entry point for embedded model verification.

    This script is called by startup.sh to verify models are embedded in the
    Docker image and accessible at runtime.

    Usage: python core/models.py
    """
    logger.info("Avatar API - Embedded Model Verification")
    logger.info("="*60)

    # Get storage path from environment or use default
    # Models embedded at /app/models/ during Docker build
    storage_path = os.getenv("MODEL_STORAGE_PATH", "/app/models")

    # Initialize manager
    manager = ModelManager(storage_path)

    try:
        # Verify models are cached by RunPod
        model_paths = manager.verify_models()

        logger.info("\n✓ All models cached and ready!")
        logger.info("Model paths:")
        for key, path in model_paths.items():
            logger.info(f"  {key}: {path}")

        return 0

    except RuntimeError as e:
        # Expected error when models are missing
        logger.error(f"\n✗ Verification failed: {e}")
        return 1
    except Exception as e:
        # Unexpected error
        logger.error(f"\n✗ Unexpected error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
