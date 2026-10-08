param(
    [string]$ApiUrl = "https://sendoh.onrender.com"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FlutterRoot = Join-Path $ProjectRoot "apps\organizer_flutter"

Push-Location $FlutterRoot
try {
    if (-not (Test-Path "android")) {
        flutter create --project-name sendoh_organizer --platforms=android,ios .
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed" }
    python ..\..\scripts\configure_mobile.py
    if ($LASTEXITCODE -ne 0) { throw "Native configuration requires review" }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "Flutter analysis failed" }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw "Flutter tests failed" }
    flutter build apk --release --dart-define="API_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
    Write-Host "APK created at apps\organizer_flutter\build\app\outputs\flutter-apk\app-release.apk"
} finally {
    Pop-Location
}
