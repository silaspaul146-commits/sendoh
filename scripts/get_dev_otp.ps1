param(
    [Parameter(Mandatory = $true)]
    [string]$ChallengeId
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BackendRoot = Join-Path $ProjectRoot "services\backend"
$Python = Join-Path $BackendRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $Python)) {
    throw "Backend virtual environment not found at $Python. Create services\backend\.venv and install requirements.lock first."
}

$env:SENDOH_ENV = "development"
Push-Location $BackendRoot
try {
    & $Python -m app.dev_otp $ChallengeId
} finally {
    Pop-Location
}
