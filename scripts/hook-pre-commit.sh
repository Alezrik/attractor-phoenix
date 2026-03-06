#!/usr/bin/env sh
set -eu

echo "[pre-commit] Checking formatting..."
mix format --check-formatted

echo "[pre-commit] Compiling with warnings as errors..."
mix compile --warnings-as-errors

echo "[pre-commit] Running Credo..."
mix credo --strict
