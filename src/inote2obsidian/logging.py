from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path


class JsonLineFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "time": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        for field in ("run_id", "note_id", "stage"):
            if hasattr(record, field):
                payload[field] = getattr(record, field)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(log_file: Path, level: str) -> logging.Logger:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("inote2obsidian")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    logger.handlers.clear()

    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setFormatter(JsonLineFormatter())
    logger.addHandler(file_handler)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(JsonLineFormatter())
    logger.addHandler(console_handler)

    return logger
