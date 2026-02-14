"""Bedrock model factory for Strands Agents."""

from __future__ import annotations

from strands.models import BedrockModel
from strands.models.model import CacheConfig

from app.config import BEDROCK_MODEL_ID, get_aws_session


def create_model(
    model_id: str = BEDROCK_MODEL_ID,
) -> BedrockModel:
    """Create a BedrockModel with prompt caching enabled."""
    session = get_aws_session()
    return BedrockModel(
        model_id=model_id,
        boto_session=session,
        cache_config=CacheConfig(strategy="auto"),
        cache_tools="default",
    )
