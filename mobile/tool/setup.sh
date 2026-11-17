#!/usr/bin/env sh
set -e
flutter create . --project-name ouaga_assainissement --org bf.ouaga --platforms=android,ios
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "ACCESS_FINE_LOCATION" "$MANIFEST"; then
  sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.CAMERA"/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application#' "$MANIFEST"
  sed -i.bak 's#<application#<application android:usesCleartextTraffic="true"#' "$MANIFEST"
  rm -f "$MANIFEST.bak"
fi
PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ] && ! grep -q NSCameraUsageDescription "$PLIST"; then
  sed -i.bak 's#</dict>\n</plist>##' "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string Photographier le dépotoir à signaler" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string Placer le signalement à votre position" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string Dicter la précision du signalement" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Dicter la précision du signalement" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string Choisir une photo du dépotoir" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST.bak"
fi
flutter pub get
echo "Configuration terminée. Lancez : flutter run --dart-define=API_BASE=http://10.0.2.2:3000"
