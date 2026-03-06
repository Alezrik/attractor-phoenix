$ErrorActionPreference = "Stop"

Write-Host "[pre-push] Running tests with warnings as errors..."
mix test --warnings-as-errors

Write-Host "[pre-push] Running Credo..."
mix credo --strict

Write-Host "[pre-push] Running Dialyzer..."
$previousMixEnv = $env:MIX_ENV
$env:MIX_ENV = "dev"
mix dialyzer --format short
$env:MIX_ENV = $previousMixEnv

Write-Host "[pre-push] Enforcing coverage gate..."
mix coveralls.json
