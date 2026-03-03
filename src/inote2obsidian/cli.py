from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

from inote2obsidian.config import load_config, write_default_config
from inote2obsidian.logging import configure_logging
from inote2obsidian.state_db import StateDB
from inote2obsidian.sync_engine import run_sync


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="inote2obsidian")
    sub = parser.add_subparsers(dest="command", required=True)

    p_sync = sub.add_parser("sync", help="Run one sync cycle")
    p_sync.add_argument("--config", required=True, type=Path)

    p_init = sub.add_parser("init-config", help="Write default YAML config")
    p_init.add_argument("--output", required=True, type=Path)

    p_doc = sub.add_parser("doctor", help="Check runtime prerequisites")
    p_doc.add_argument("--config", required=True, type=Path)

    p_status = sub.add_parser("status", help="Show latest sync run")
    p_status.add_argument("--config", required=True, type=Path)

    return parser


def _doctor(config_path: Path) -> int:
    cfg = load_config(config_path)
    checks: list[dict[str, str]] = []

    vault = Path(cfg.obsidian.vault_path)
    vault.mkdir(parents=True, exist_ok=True)
    checks.append({"check": "vault_writable", "ok": str(os.access(vault, os.W_OK))})

    db_path = Path(cfg.state.db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    checks.append({"check": "db_dir_writable", "ok": str(os.access(db_path.parent, os.W_OK))})

    probe = subprocess.run(["osascript", "-e", 'return "ok"'], capture_output=True, text=True)
    checks.append(
        {
            "check": "osascript_available",
            "ok": str(probe.returncode == 0),
            "hint": "Grant Automation permission when first Apple Notes access prompt appears.",
        }
    )

    print(json.dumps(checks, ensure_ascii=False, indent=2))
    return 0 if all(c["ok"] == "True" for c in checks) else 2


def _status(config_path: Path) -> int:
    cfg = load_config(config_path)
    db = StateDB(Path(cfg.state.db_path))
    db.init_schema()
    row = db.get_last_run()
    if row is None:
        print("No sync run yet")
        return 0
    print(json.dumps(dict(row), ensure_ascii=False, indent=2))
    return 0


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    if args.command == "init-config":
        write_default_config(args.output)
        print(f"Config generated at {args.output}")
        return 0

    if args.command == "doctor":
        return _doctor(args.config)

    if args.command == "status":
        return _status(args.config)

    if args.command == "sync":
        cfg = load_config(args.config)
        logger = configure_logging(Path(cfg.logging.file_path), cfg.logging.level)
        status, stats = run_sync(cfg, logger)
        print(
            json.dumps(
                {
                    "status": status,
                    "added": stats.added_count,
                    "updated": stats.updated_count,
                    "deleted": stats.deleted_count,
                    "errors": stats.error_count,
                    "skipped": stats.skipped_count,
                },
                ensure_ascii=False,
            )
        )
        return 0 if status in {"success", "partial"} else 1

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
