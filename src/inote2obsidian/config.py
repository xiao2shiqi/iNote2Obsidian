from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path

import yaml


@dataclass
class AppleNotesConfig:
    folder_name: str = "Diary"


@dataclass
class ObsidianConfig:
    vault_path: str = "/tmp/obsidian-vault"
    notes_subdir: str = "AppleNotes"
    assets_subdir: str = "AppleNotes/_assets"


@dataclass
class SyncConfig:
    timezone: str = "Asia/Shanghai"
    filename_strategy: str = "id_slug"
    deletion_mode: str = "tombstone_only"
    hash_algo: str = "sha256"


@dataclass
class StateConfig:
    db_path: str = "/tmp/.inote2obsidian/state.db"


@dataclass
class LoggingConfig:
    level: str = "INFO"
    file_path: str = "/tmp/.inote2obsidian/sync.log"


@dataclass
class AppConfig:
    apple_notes: AppleNotesConfig
    obsidian: ObsidianConfig
    sync: SyncConfig
    state: StateConfig
    logging: LoggingConfig


def default_config() -> AppConfig:
    return AppConfig(
        apple_notes=AppleNotesConfig(),
        obsidian=ObsidianConfig(),
        sync=SyncConfig(),
        state=StateConfig(),
        logging=LoggingConfig(),
    )


def write_default_config(path: Path) -> None:
    cfg = default_config()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(asdict(cfg), fh, sort_keys=False, allow_unicode=True)


def load_config(path: Path) -> AppConfig:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("Config file must be a YAML object")

    def section(name: str) -> dict:
        value = raw.get(name)
        if not isinstance(value, dict):
            raise ValueError(f"Missing or invalid config section: {name}")
        return value

    return AppConfig(
        apple_notes=AppleNotesConfig(**section("apple_notes")),
        obsidian=ObsidianConfig(**section("obsidian")),
        sync=SyncConfig(**section("sync")),
        state=StateConfig(**section("state")),
        logging=LoggingConfig(**section("logging")),
    )
