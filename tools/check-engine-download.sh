#!/usr/bin/env bash
set -euo pipefail

# Official Godot 4.7.2 release, verified against its SHA512-SUMS.txt.
archive=Godot_v4.7.2-stable_linux.x86_64.zip
expected=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
engine_dir="${RUNNER_TEMP:?RUNNER_TEMP must point to a disposable CI directory}/godot"
mkdir -p "$engine_dir"
curl --fail --location --retry 3 \
  "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$archive" \
  --output "$engine_dir/$archive"
printf '%s  %s\n' "$expected" "$engine_dir/$archive" | sha512sum --check
unzip -q "$engine_dir/$archive" -d "$engine_dir"
chmod +x "$engine_dir/Godot_v4.7.2-stable_linux.x86_64"
printf '%s\n' "$engine_dir/Godot_v4.7.2-stable_linux.x86_64"
