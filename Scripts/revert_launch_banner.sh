#!/usr/bin/env bash
set -euo pipefail

SMOKE_BANNER="Sources/UI/Root/LaunchBanner.swift"
APP_FILE="Sources/UI/Root/StupidUnderdogApp.swift"

# Remove LaunchBanner view file if present
if [ -f "$SMOKE_BANNER" ]; then
  git rm -f "$SMOKE_BANNER" > /dev/null 2>&1 || rm -f "$SMOKE_BANNER"
fi

# Replace LaunchBanner() with RootView() inside the app entry
if [ -f "$APP_FILE" ]; then
  perl -0777 -pe 's/LaunchBanner\(\)([\s\S]*?)\}/RootView\(\)\1}/m' -i "$APP_FILE"
fi

echo "Reverted launch banner."


