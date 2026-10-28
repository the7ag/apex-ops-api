"""Structured (JSON) logging to stdout so `docker compose logs` can be parsed by any log tool."""

import logging
import sys

from pythonjsonlogger.json import JsonFormatter


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        JsonFormatter(
            "%(asctime)s %(levelname)s %(name)s %(message)s",
            rename_fields={"asctime": "timestamp", "levelname": "level", "name": "logger"},
        )
    )
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)

    # Route uvicorn's own logs through the JSON handler too.
    for name in ("uvicorn", "uvicorn.error"):
        uv = logging.getLogger(name)
        uv.handlers.clear()
        uv.propagate = True
