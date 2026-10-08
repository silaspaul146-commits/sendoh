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
    flutter analyze
    flutter test
    flutter build apk --release --dart-define="API_URL=$ApiUrl"
    Write-Host "APK created at apps\organizer_flutter\build\app\outputs\flutter-apk\app-release.apk"
} finally {
    Pop-Location
}
