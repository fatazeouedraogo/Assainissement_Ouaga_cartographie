$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Test-Path "android")) {
    flutter create --project-name ouagaclean --org bf.ouagaclean .
}

$manifest = "android\app\src\main\AndroidManifest.xml"
$x = Get-Content $manifest -Raw

if ($x -notmatch "ACCESS_FINE_LOCATION") {
    $perm = @"

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>
"@
    $x = $x -replace "(<manifest[^>]*>)", "`$1$perm"
}

if ($x -notmatch "usesCleartextTraffic") {
    $x = $x -replace "<application", '<application android:usesCleartextTraffic="true"'
}

if ($x -notmatch "RECORD_AUDIO") {
    $x = $x -replace "(<manifest[^>]*>)", "`$1`n    <uses-permission android:name=`"android.permission.RECORD_AUDIO`"/>"
}

Set-Content $manifest $x -Encoding UTF8

# Le micro (paquet record) demande Android 6 minimum (minSdk 23).
foreach ($g in @("android\app\build.gradle.kts", "android\app\build.gradle")) {
    if (Test-Path $g) {
        $t = Get-Content $g -Raw
        $t = $t -replace "minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23"
        $t = $t -replace "minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23"
        Set-Content $g $t -Encoding UTF8
    }
}

flutter pub get
flutter analyze
Write-Host ""
Write-Host "Prêt. Lancement : flutter run --dart-define=API_BASE=http://IP_DU_PC:3000"
