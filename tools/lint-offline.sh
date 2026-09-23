#!/usr/bin/env bash
# Format check + lint without network access (cloud/sandbox sessions).
# selene resolves a custom std from the working directory, so the minimal
# Roblox std is copied to the repo root for the run and removed afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
trap 'rm -f robloxlite.yml' EXIT
cp tools/lint/robloxlite.yml robloxlite.yml
stylua --check src
selene --config tools/lint/selene-offline.toml src
