#!/bin/bash
set -euo pipefail
# 1.0.0 is distributed manually via GitHub Releases, without an OTA updater.
# This prepares local artifacts only. It never uploads or publishes a release.
exec bash "$(dirname "$0")/build_app.sh" "$@"
