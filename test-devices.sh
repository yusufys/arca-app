#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHP_BIN="/Users/yusuf/Library/Application Support/Herd/bin/php"
if [ ! -x "$PHP_BIN" ]; then
  PHP_BIN="$(which php)"
fi
ADB_BIN="$ROOT_DIR/.tools/sdk/platform-tools/adb"
if [ ! -x "$ADB_BIN" ]; then
  ADB_BIN="$(which adb 2>/dev/null || true)"
fi

# 1. Detect Mac's Local Wi-Fi IP
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")"
API_URL="http://${LAN_IP}:8000"

echo "========================================================"
echo "🚀 Arca Fast Wireless Device Tester"
echo "========================================================"
echo "📡 Local Wi-Fi API URL:  ${API_URL}"
echo "📲 Wireless APK URL:     ${API_URL}/download-apk"
echo "🖥  Admin & QR Page:      ${API_URL}/admin"
echo "========================================================"

# 2. Point Android & iOS configs to Mac's Wi-Fi IP
if [ -f "$ROOT_DIR/android/local.properties" ]; then
  grep -v "^ARCA_API_BASE_URL=" "$ROOT_DIR/android/local.properties" > "$ROOT_DIR/android/local.properties.tmp" || true
  mv "$ROOT_DIR/android/local.properties.tmp" "$ROOT_DIR/android/local.properties"
fi
echo "ARCA_API_BASE_URL=${API_URL}" >> "$ROOT_DIR/android/local.properties"

# 3. Build fresh Android APK with live Wi-Fi IP
echo "🔨 Building fresh Arca-debug.apk..."
(
  cd "$ROOT_DIR/android"
  GRADLE_USER_HOME="$ROOT_DIR/.tools/gradle_home" \
  ANDROID_USER_HOME="$ROOT_DIR/.tools/android_home" \
  ANDROID_HOME="$ROOT_DIR/.tools/sdk" \
  ./gradlew assembleDebug --no-daemon -q
  cp app/build/outputs/apk/debug/app-debug.apk "$ROOT_DIR/Arca-debug.apk"
)
echo "✅ Updated Arca-debug.apk (pointing to ${API_URL})"

# 4. If an Android phone is connected via USB or Wireless ADB, auto-install & launch!
if [ -n "$ADB_BIN" ] && [ -x "$ADB_BIN" ]; then
  CONNECTED_DEVICES="$("$ADB_BIN" devices | awk 'NR>1 && $2=="device" {print $1}')"
  if [ -n "$CONNECTED_DEVICES" ]; then
    for DEV in $CONNECTED_DEVICES; do
      echo "📲 Auto-installing & launching on connected Android device ($DEV)..."
      "$ADB_BIN" -s "$DEV" install -r "$ROOT_DIR/Arca-debug.apk"
      "$ADB_BIN" -s "$DEV" shell monkey -p app.arca.personalrecords -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    done
  else
    echo "💡 No ADB cable connected — scan the QR code at ${API_URL}/admin on your phone to install over Wi-Fi!"
  fi
fi

# 5. Ensure Laravel SQLite DB is migrated & seeded
(
  cd "$ROOT_DIR/backend"
  "$PHP_BIN" artisan migrate --seed --force >/dev/null 2>&1 || true
)

# 6. Open the Admin + QR Code page on Mac & start Laravel server on 0.0.0.0:8000
open "${API_URL}/admin" >/dev/null 2>&1 || true
echo ""
echo "🌐 Starting Laravel Backend on 0.0.0.0:8000 (Press Ctrl+C to stop)..."
cd "$ROOT_DIR/backend"
exec "$PHP_BIN" artisan serve --host=0.0.0.0 --port=8000
