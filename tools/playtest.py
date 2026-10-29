#!/usr/bin/env python3
"""Run a disposable graphical playtest without touching normal game saves."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from isolated_project import cleanup, prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--save", type=Path, help="Copy an existing reviewed test save into the disposable session")
    parser.add_argument("--log-file", type=Path, required=True)
    parser.add_argument("--time-scale", type=float, default=1.0)
    args = parser.parse_args()
    args.log_file.resolve().parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="strategy-playtest-") as directory:
        runtime = prepare(Path(__file__).resolve().parents[1], Path(directory), Path(args.godot))
        try:
            command = [str(runtime["engine"]), "--path", str(runtime["project"]), "--log-file", str(args.log_file.resolve())]
            probe = subprocess.run([*command, "--headless", "--script", "res://isolation_probe.gd"],
                                   env=runtime["env"], capture_output=True, text=True, timeout=30)
            if probe.returncode or "ISOLATION:" + str(runtime["user_data"]) not in probe.stdout:
                raise RuntimeError("Cannot verify isolated user data")
            imported = subprocess.run([*command, "--headless", "--import"], env=runtime["env"], capture_output=True, text=True, timeout=120)
            if imported.returncode or "ERROR:" in imported.stdout + imported.stderr:
                raise RuntimeError(imported.stdout + imported.stderr)
            if args.save:
                saves = runtime["user_data"] / "saves"
                saves.mkdir(exist_ok=True)
                shutil.copyfile(args.save, saves / "manual_save.json")
            print("PLAYTEST_APP=" + str(runtime["engine"].parents[2]), flush=True)
            print("PLAYTEST_PROJECT=" + str(runtime["project"]), flush=True)
            print("Disposable session. Closing the window discards its saves.", flush=True)
            return subprocess.run([*command, "--max-fps", "60", "--time-scale", str(args.time_scale)], env=runtime["env"]).returncode
        finally:
            cleanup(runtime)


if __name__ == "__main__":
    raise SystemExit(main())
