"""
Model Download Manager for Avatar API
Handles downloading and caching of InfiniteTalk models to RunPod persistent storage.
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
    Manages downloading and caching of ML models for InfiniteTalk.

    Models are downloaded to RunPod persistent storage (/runpod-volume/models/)
    to avoid re-downloading on every container restart.
    """

    # Model configurations
    MODELS = {
        "wan2.1-i2v-14b": {
            "repo_id": "Wan-AI/Wan2.1-I2V-14B-480P",
            "local_dir": "Wan2.1-I2V-14B-480P",
            "size_gb": 40,
            "description": "Wan 2.1 Image-to-Video 14B model"
        },
        "chinese-wav2vec2": {
            "repo_id": "TencentGameMate/chinese-wav2vec2-base",
            "local_dir": "chinese-wav2vec2-base",
            "size_gb": 1,
            "description": "Chinese Wav2Vec2 audio encoder"
        },
        "infinitetalk": {
            "repo_id": "MeiGen-AI/InfiniteTalk",
            "local_dir": "InfiniteTalk",
            "size_gb": 2,
            "description": "InfiniteTalk weights and audio conditioning"
        }
    }

    def __init__(self, storage_path: str = "/runpod-volume/models"):
        """
        Initialize ModelManager.

        Args:
            storage_path: Path to persistent storage directory (default: /runpod-volume/models)
        """
        self.storage_path = Path(storage_path)
        self.hf_token = os.getenv("HF_TOKEN")

        # Create storage directory if it doesn't exist
        self.storage_path.mkdir(parents=True, exist_ok=True)

        logger.info(f"ModelManager initialized with storage path: {self.storage_path}")
        if not self.hf_token:
            logger.warning("HF_TOKEN not set - public models only")

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
    CLI entry point for model download.
    Usage: python core/models.py
    """
    logger.info("Avatar API - Model Download Manager")
    logger.info("="*60)

    # Get storage path from environment or use default
    storage_path = os.getenv("MODEL_STORAGE_PATH", "/runpod-volume/models")

    # Initialize manager and download models
    manager = ModelManager(storage_path)

    try:
        model_paths = manager.ensure_models_downloaded()

        logger.info("\n✓ All models ready!")
        logger.info("Model paths:")
        for key, path in model_paths.items():
            logger.info(f"  {key}: {path}")

        return 0

    except Exception as e:
        logger.error(f"\n✗ Model download failed: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
