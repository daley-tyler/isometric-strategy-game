"""Stage disposable project/import data and a portable copy of the installed engine."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import uuid


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def prepare(source, workspace, executable):
    source, workspace, executable = Path(source).resolve(), Path(workspace).resolve(), Path(executable).resolve()
    project = workspace / "project"
    shutil.copytree(source, project, ignore=shutil.ignore_patterns(
        ".git", ".godot", "test-results", "__pycache__", "builds", "captures", "saves"))
    engine_dir = workspace / "engine"
    engine_dir.mkdir()
    if sys.platform == "darwin" and executable.parent.name == "MacOS":
        # Keep the signed app bundle intact; a bare copied macOS executable
        # may be terminated by the OS before it can report diagnostics.
        bundle = executable.parents[2]
        staged_bundle = engine_dir / bundle.name
        shutil.copytree(bundle, staged_bundle)
        engine = staged_bundle / "Contents/MacOS" / executable.name
        marker_dir = staged_bundle / "Contents"
    else:
        engine = engine_dir / executable.name
        shutil.copy2(executable, engine)
        marker_dir = engine_dir
    if digest(engine) != digest(executable):
        raise RuntimeError("Staged engine does not match the installed executable")
    # macOS portable installations detect the marker beside the .app bundle.
    (engine_dir / "_sc_").touch()
    (marker_dir / "_sc_").touch()
    identity = "Isometric Strategy Validation/" + uuid.uuid4().hex
    config = project / "project.godot"
    lines = config.read_text().splitlines()
    for index, line in enumerate(lines):
        if line.startswith("config/use_custom_user_dir="):
            lines[index] = "config/use_custom_user_dir=true"
        elif line.startswith("config/custom_user_dir_name="):
            lines[index] = "config/custom_user_dir_name=" + json.dumps(identity)
    config.write_text("\n".join(lines) + "\n")
    env = os.environ.copy()
    # Linux respects XDG paths; macOS editor data uses the staged _sc_ marker.
    for name, part in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        env[name] = str(workspace / "xdg" / part)
    if sys.platform == "darwin":
        data_base = Path.home() / "Library/Application Support"
    elif sys.platform == "win32":
        data_base = Path(os.environ["APPDATA"])
    else:
        data_base = Path(env["XDG_DATA_HOME"])
    user_data = data_base / identity
    # The marker authorizes cleanup of this randomly named test directory only.
    user_data.mkdir(parents=True, exist_ok=False)
    marker = user_data / ".strategy-validation-owner"
    marker.write_text(str(workspace))
    probe = project / "isolation_probe.gd"
    probe.write_text('extends SceneTree\nfunc _init() -> void:\n\tprint("ISOLATION:" + OS.get_user_data_dir())\n\tquit()\n')
    return {"project": project, "engine": engine, "env": env, "user_data": user_data,
            "marker": marker, "workspace": workspace, "portable_marker": marker_dir / "_sc_"}


def cleanup(runtime):
    marker = runtime["marker"]
    if marker.is_file() and marker.read_text() == str(runtime["workspace"]):
        shutil.rmtree(runtime["user_data"])
