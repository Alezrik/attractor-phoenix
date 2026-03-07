$ErrorActionPreference = "Stop"

Write-Host "[pre-push] Running shared precommit checks (including coverage gate)..."
mix precommit

Write-Host "[pre-push] Running Dialyzer..."
$previousMixEnv = $env:MIX_ENV
$env:MIX_ENV = "dev"
mix dialyzer --format short
$env:MIX_ENV = $previousMixEnv
