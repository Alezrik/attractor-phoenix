#!/usr/bin/env sh
set -eu

echo "[pre-push] Running shared precommit checks (including coverage gate)..."
mix precommit

echo "[pre-push] Running Dialyzer..."
MIX_ENV=dev mix dialyzer --format short
