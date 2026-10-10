param(
    [string]$ApiUrl = "https://sendoh.onrender.com",
    [string]$PushConfig = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FlutterRoot = Join-Path $ProjectRoot "apps\organizer_flutter"
$ResolvedPushConfig = if ($PushConfig) { (Resolve-Path $PushConfig).Path } else { "" }
$PushBuildFile = Join-Path ([System.IO.Path]::GetTempPath()) ("sendoh-push-" + [guid]::NewGuid().ToString() + ".json")

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
    if ($ResolvedPushConfig) {
        python ..\..\scripts\prepare_push_build.py --config $ResolvedPushConfig --output $PushBuildFile --android-root android
    } else {
        python ..\..\scripts\prepare_push_build.py --output $PushBuildFile --android-root android
    }
    if ($LASTEXITCODE -ne 0) { throw "Invalid push configuration" }
    flutter build apk --release --dart-define="API_URL=$ApiUrl" --dart-define-from-file=$PushBuildFile
    if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
    Write-Host "APK created at apps\organizer_flutter\build\app\outputs\flutter-apk\app-release.apk"
} finally {
    Remove-Item $PushBuildFile -ErrorAction SilentlyContinue
    Pop-Location
}
