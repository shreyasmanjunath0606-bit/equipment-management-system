#!/usr/bin/env bash
# Builds the Flutter web app on Vercel (Vercel has no Flutter preinstalled).
# Vercel project settings: Root Directory = flutter_app; env vars SUPABASE_URL,
# SUPABASE_ANON_KEY (and optionally SITE_URL).
set -euo pipefail

FLUTTER_VERSION="3.47.9" # keep in step with the version used locally
FLUTTER_DIR="$HOME/flutter-sdk"

: "${SUPABASE_URL:?Set SUPABASE_URL in the Vercel project environment variables}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY in the Vercel project environment variables}"

if ! command -v unzip >/dev/null 2>&1; then
  dnf install -y unzip >/dev/null
fi

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --no-analytics >/dev/null
flutter --version
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=SITE_URL="${SITE_URL:-}"
