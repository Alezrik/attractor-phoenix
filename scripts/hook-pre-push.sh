#!/usr/bin/env sh
set -eu

echo "[pre-push] Running tests with warnings as errors..."
mix test --warnings-as-errors

echo "[pre-push] Running Credo..."
mix credo --strict

echo "[pre-push] Running Dialyzer..."
MIX_ENV=dev mix dialyzer --format short

echo "[pre-push] Enforcing coverage gate..."
mix coveralls.json
