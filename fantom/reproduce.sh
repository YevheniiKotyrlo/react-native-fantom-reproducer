#!/usr/bin/env bash
# Builds the image and runs one case in a container of its own. Usage: ./fantom/reproduce.sh <case> [<react-native ref>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && { pwd -W 2>/dev/null || pwd; })"
docker build --tag react-native-fantom-reproducer "$here"
# ThreadSanitizer and LeakSanitizer re-execute or stop the process through calls Docker's default seccomp profile refuses.
docker run --rm --init --security-opt seccomp=unconfined \
  --mount "type=bind,source=$here,target=/reproducer/fantom,readonly" \
  --mount type=volume,source=react-native-fantom-reproducer-cache,target=/cache \
  --env GRADLE_USER_HOME=/cache/gradle --env YARN_CACHE_FOLDER=/cache/yarn --env REACT_NATIVE_DOWNLOADS_DIR=/cache/downloads \
  react-native-fantom-reproducer bash /reproducer/fantom/run-case.sh "$1" "${2:-main}"
