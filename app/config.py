"""Dual-mode config: local development vs AgentCore production."""

from __future__ import annotations

import logging
import os
from pathlib import Path

import boto3
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

_env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=_env_path)

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "local")
AWS_REGION: str = os.getenv("AWS_REGION", "us-east-1")
AWS_PROFILE: str | None = os.getenv("AWS_PROFILE")

# ---------------------------------------------------------------------------
# Bedrock model
# ---------------------------------------------------------------------------
BEDROCK_MODEL_ID: str = os.getenv(
    "BEDROCK_MODEL_ID",
    "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
)

# ---------------------------------------------------------------------------
# AgentCore Memory
# ---------------------------------------------------------------------------
MEMORY_ENABLED: bool = os.getenv("MEMORY_ENABLED", "false").lower() in (
    "true",
    "1",
    "yes",
)
MEMORY_ID: str = os.getenv("MEMORY_ID", "")
MEMORY_SUMMARIZATION_STRATEGY_ID: str = os.getenv(
    "MEMORY_SUMMARIZATION_STRATEGY_ID", ""
)


def get_aws_session() -> boto3.Session:
    """Return a boto3 Session for the current environment."""
    if ENVIRONMENT == "local":
        logger.info("AWS session: profile=%s region=%s", AWS_PROFILE, AWS_REGION)
        return boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
    logger.info("AWS session: IAM role (agentcore) region=%s", AWS_REGION)
    return boto3.Session(region_name=AWS_REGION)


def get_memory_id() -> str | None:
    """Return the Memory resource ID if memory is enabled, else None."""
    if MEMORY_ENABLED and MEMORY_ID:
        logger.info("Memory enabled: id=%s", MEMORY_ID)
        return MEMORY_ID
    return None
