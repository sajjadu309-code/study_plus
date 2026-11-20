param(
  [string]$WebClientId = "",
  [switch]$BuildApk
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
Write-Host "StudyPulse Mobile Pro — Windows project setup" -ForegroundColor Cyan

if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter was not found. Open a terminal with flutter in PATH."
}

$jdk = "C:\Users\Ideal Computer\AppData\Local\Programs\Eclipse Adoptium\jdk-17.0.21.9-hotspot"
if (Test-Path "$jdk\bin\java.exe") {
  $env:JAVA_HOME = $jdk
  $env:Path = "$jdk\bin;$env:Path"
  flutter config --jdk-dir="$jdk"
  if ($LASTEXITCODE -ne 0) { throw "Flutter JDK configuration failed" }
}

if (!(Test-Path "android\app\build.gradle.kts")) {
  flutter create --org com.example --project-name study_pulse_mobile --platforms android,web .
  if ($LASTEXITCODE -ne 0) { throw "Flutter platform generation failed" }
}
# Flutter's generated starter test may reference a nonexistent MyApp class.
$starterTest = Join-Path $PSScriptRoot "test\widget_test.dart"
if ((Test-Path $starterTest) -and ((Get-Content $starterTest -Raw) -match 'MyApp')) {
  Remove-Item $starterTest -Force
}

$manifestPath = Join-Path $PSScriptRoot "android\app\src\main\AndroidManifest.xml"
$manifest = Get-Content $manifestPath -Raw
foreach ($permission in @(
  "android.permission.INTERNET",
  "android.permission.POST_NOTIFICATIONS",
  "android.permission.RECEIVE_BOOT_COMPLETED"
)) {
  if ($manifest -notmatch [regex]::Escape($permission)) {
    $line = "    <uses-permission android:name=`"$permission`" />"
    $manifest = $manifest.Replace('<application', "$line`n    <application")
  }
}
if ($manifest -notmatch 'ScheduledNotificationReceiver') {
  $receivers = @'
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" android:exported="false" />
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'@
  $manifest=$manifest.Replace('</application>', "$receivers`n    </application>")
}
[System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))

$gradlePath = Join-Path $PSScriptRoot "android\app\build.gradle.kts"
$gradle = Get-Content $gradlePath -Raw
if ($gradle -notmatch 'isCoreLibraryDesugaringEnabled') {
  $gradle = $gradle.Replace('compileOptions {', "compileOptions {`n        isCoreLibraryDesugaringEnabled = true")
}
if ($gradle -notmatch 'coreLibraryDesugaring\(') {
  $gradle += "`n`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`" )`n}`n"
}
$gradle = [regex]::Replace($gradle,'(?m)^\s*compileSdk\s*=\s*.*$', '    compileSdk = 36')
[System.IO.File]::WriteAllText($gradlePath, $gradle, (New-Object System.Text.UTF8Encoding($false)))

$properties = Join-Path $PSScriptRoot "android\gradle.properties"
$settings = Get-Content $properties -Raw
if ($settings -match '(?m)^\s*kotlin\.incremental\s*=') {
  $settings=[regex]::Replace($settings,'(?m)^\s*kotlin\.incremental\s*=.*$', 'kotlin.incremental=false')
} else { $settings += "`nkotlin.incremental=false`n" }
[System.IO.File]::WriteAllText($properties, $settings, (New-Object System.Text.UTF8Encoding($false)))

$env:PUB_CACHE = "E:\FlutterPubCache"
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed" }
flutter analyze --no-pub
if ($LASTEXITCODE -ne 0) { throw "Flutter analysis found issues. Fix them before APK build." }
flutter test
if ($LASTEXITCODE -ne 0) { throw "Flutter tests failed. Fix them before APK build." }
Write-Host "Code analysis and unit tests completed successfully." -ForegroundColor Green

if ($BuildApk) {
  if ([string]::IsNullOrWhiteSpace($WebClientId)) {
    Write-Host "No Google OAuth Web Client ID provided. Drive backup will not authenticate." -ForegroundColor Yellow
    flutter build apk --release
  } else {
    flutter build apk --release "--dart-define=GOOGLE_WEB_CLIENT_ID=$WebClientId"
  }
  if ($LASTEXITCODE -ne 0) { throw "APK build failed; inspect the terminal output." }
  $apk=Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (!(Test-Path $apk)) { throw "Build finished but APK was not found" }
  Write-Host "APK generated at: $apk" -ForegroundColor Green
}
