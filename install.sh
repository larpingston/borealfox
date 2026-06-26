#!/bin/sh
set -e

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
  /*) ;;
  *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
esac
REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

find_profile() {
  local found_dir=""
  for base in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
    if [ -d "$base" ]; then
      rel="$(find "$base" -maxdepth 1 -iname "*.default-release" 2>/dev/null | head -n 1)"
      if [ -n "$rel" ]; then
        found_dir="$rel"
        break
      fi
    fi
  done

  if [ -z "$found_dir" ]; then
    for base in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
      if [ -d "$base" ]; then
        found="$(find "$base" -maxdepth 1 -iname "*.default" 2>/dev/null | head -n 1)"
        if [ -n "$found" ]; then
          found_dir="$found"
          break
        fi
      fi
    done
  fi
  echo "$found_dir"
}

PROFILE_DIR=$(find_profile)

FIREFOX_PATH="$(command -v firefox)"

if [ -z "$PROFILE_DIR" ]; then
  echo "no firefox profile found, creating firefox profile..."
  "$FIREFOX_PATH" --headless >/dev/null 2>&1 &
  FIREFOX_PID=$!
  sleep 4
  kill $FIREFOX_PID 2>/dev/null || pkill -f firefox || true
  sleep 1
  
  PROFILE_DIR=$(find_profile)
  
  if [ -z "$PROFILE_DIR" ]; then
    echo "[ error ] failed to create firefox profile, launch firefox once manually then rerun this script"
    exit 1
  fi
fi

FIREFOX_PATH="$(command -v firefox)"
FIREFOX_BIN="$(readlink -f "$FIREFOX_PATH" 2>/dev/null || echo "$FIREFOX_PATH")"
FIREFOX_DIR="$(dirname "$FIREFOX_BIN")"

if [ ! -f "$FIREFOX_DIR/application.ini" ]; then
  for candidate in /usr/lib/firefox /usr/lib64/firefox /usr/lib/firefox-esr /opt/firefox /usr/share/firefox; do
    if [ -f "$candidate/application.ini" ]; then
      FIREFOX_DIR="$candidate"
      break
    fi
  done
fi

if [ ! -f "$FIREFOX_DIR/application.ini" ]; then
  echo "error: could not locate the Firefox installation directory (tried dirname of binary and common paths)"
  echo "       please set FIREFOX_DIR manually in this script"
  exit 1
fi

echo "profile: $PROFILE_DIR"
echo "install dir: $FIREFOX_DIR"

cp "$REPO_DIR/patches/user.js" "$PROFILE_DIR/user.js"

mkdir -p "$PROFILE_DIR/chrome"
cp "$REPO_DIR/patches/userChrome.css" "$PROFILE_DIR/chrome/userChrome.css"
if [ -f "$REPO_DIR/patches/logo.png" ]; then
  cp "$REPO_DIR/patches/logo.png" "$PROFILE_DIR/chrome/logo.png"
fi

sudo mkdir -p "$FIREFOX_DIR/distribution"
sudo cp "$REPO_DIR/distribution/policies.json" "$FIREFOX_DIR/distribution/policies.json"

pkill -f firefox || true
sleep 1

rm -f "$PROFILE_DIR/sessionstore.jsonlz4"
rm -f "$PROFILE_DIR/sessionstore-backups"/recovery.jsonlz4
rm -f "$PROFILE_DIR/sessionstore-backups"/previous.jsonlz4
rm -f "$PROFILE_DIR/sessionstore-backups"/recovery.baklz4

"$FIREFOX_PATH" "file://$REPO_DIR/patches/splash.html" &
sleep 12

pkill -f firefox || true
sleep 1

rm -f "$PROFILE_DIR/sessionstore.jsonlz4"
rm -f "$PROFILE_DIR/sessionstore-backups"/recovery.jsonlz4
rm -f "$PROFILE_DIR/sessionstore-backups"/previous.jsonlz4
rm -f "$PROFILE_DIR/sessionstore-backups"/recovery.baklz4

echo "done, launching borealfox..."
"$FIREFOX_PATH" &
