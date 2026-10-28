"""All configuration comes from environment variables (12-factor style)."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_url: str
    app_version: str
    log_level: str


def get_settings() -> Settings:
    return Settings(
        database_url=os.getenv("DATABASE_URL", "sqlite:///./local.db"),
        app_version=os.getenv("APP_VERSION", "dev"),
        log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
    )
