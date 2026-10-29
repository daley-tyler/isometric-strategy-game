#!/usr/bin/env python3
"""Import and validate a disposable project copy with isolated engine and save data."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from isolated_project import cleanup, prepare


def run_checks(root, engine, results_dir, env):
    version = subprocess.run([str(engine), "--version"], env=env, capture_output=True, text=True, timeout=20)
    if version.returncode or not version.stdout.strip().startswith("4.7.2.stable."):
        raise RuntimeError("Validation requires Godot 4.7.2 stable; received " + version.stdout.strip())
    commands = [("isolation", ["--script", "res://isolation_probe.gd"]), ("import", ["--import"])]
    commands.extend((p.stem, ["--script", "res://" + p.relative_to(root).as_posix()])
                    for p in sorted((root / "tests").glob("*_validation.gd")))
    commands.append(("main_scene", ["--quit-after", "120", "--fixed-fps", "60"]))
    records = []
    for name, options in commands:
        command = [str(engine), "--headless", "--path", str(root),
                   "--log-file", str(results_dir / f"{name}.engine.log"), *options]
        started = time.monotonic()
        try:
            result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            diagnostics = bool(re.search(r"(?:SCRIPT ERROR:|ERROR:|WARNING:.*leaked|resources still in use)", output))
            passed = result.returncode == 0 and not diagnostics
            if name.endswith("_validation"):
                passed = passed and "validation passed:" in output
            if name == "isolation":
                passed = passed and "ISOLATION:" in output
            record = {"name": name, "passed": passed, "exit_code": result.returncode,
                      "diagnostics": diagnostics, "seconds": round(time.monotonic() - started, 3)}
        except subprocess.TimeoutExpired as error:
            output = str(error)
            record = {"name": name, "passed": False, "timeout": True}
        (results_dir / f"{name}.log").write_text(output)
        records.append(record)
        print(f"{'PASS' if record['passed'] else 'FAIL'} {name}", flush=True)
        if not record["passed"]:
            print(output[-6000:], flush=True)
        if name in ("import", "isolation") and not record["passed"]:
            break
    (results_dir / "results.json").write_text(json.dumps({"godot": version.stdout.strip(), "checks": records}, indent=2) + "\n")
    return all(item["passed"] for item in records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or shutil.which("godot4"))
    parser.add_argument("--results-dir", type=Path)
    args = parser.parse_args()
    if not args.godot:
        parser.error("Pass --godot /path/to/Godot or put godot on PATH")
    source = Path(__file__).resolve().parents[1]
    results_dir = (args.results_dir or Path(tempfile.mkdtemp(prefix="strategy-results-"))).resolve()
    results_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="strategy-validation-") as directory:
        runtime = prepare(source, Path(directory), Path(args.godot))
        try:
            # Check the actual engine-resolved path before importing or starting Main.
            probe = runtime["project"] / "isolation_probe.gd"
            probe.write_text('extends SceneTree\nfunc _init() -> void:\n\tvar expected := OS.get_environment("STRATEGY_EXPECTED_USER_DATA")\n\tprint("ISOLATION:" + OS.get_user_data_dir())\n\tquit(0 if OS.get_user_data_dir() == expected else 1)\n')
            runtime["env"]["STRATEGY_EXPECTED_USER_DATA"] = str(runtime["user_data"])
            passed = run_checks(runtime["project"], runtime["engine"], results_dir, runtime["env"])
            portable = runtime["workspace"] / "engine/editor_data"
            if not portable.is_dir():
                raise RuntimeError("Godot did not enable portable editor-data isolation")
        finally:
            cleanup(runtime)
    print(f"Logs: {results_dir}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
