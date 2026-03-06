$ErrorActionPreference = "Stop"

Write-Host "[pre-commit] Checking formatting..."
mix format --check-formatted

Write-Host "[pre-commit] Compiling with warnings as errors..."
mix compile --warnings-as-errors

