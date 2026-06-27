#!/bin/sh
set -e

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
  /*) ;;
  *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
esac
REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

find_profile() {
  for base in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
    if [ -d "$base" ]; then
      rel="$(find "$base" -maxdepth 1 -iname "*.default-release" 2>/dev/null | head -n 1)"
      if [ -n "$rel" ]; then echo "$rel"; return; fi
    fi
  done
  for base in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
    if [ -d "$base" ]; then
      found="$(find "$base" -maxdepth 1 -iname "*.default" 2>/dev/null | head -n 1)"
      if [ -n "$found" ]; then echo "$found"; return; fi
    fi
  done
}

FIREFOX_PATH="$(command -v firefox)"

PROFILE_DIR=$(find_profile)
if [ -z "$PROFILE_DIR" ]; then
  echo "no firefox profile found, creating one..."
  "$FIREFOX_PATH" --headless >/dev/null 2>&1 &
  FIREFOX_PID=$!
  sleep 4
  kill $FIREFOX_PID 2>/dev/null || pkill -f firefox || true
  sleep 1
  PROFILE_DIR=$(find_profile)
  if [ -z "$PROFILE_DIR" ]; then
    echo "[ error ] could not create firefox profile. launch firefox once manually then rerun."
    exit 1
  fi
fi

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
  echo "[ error ] could not locate firefox install directory."
  exit 1
fi

echo "profile:     $PROFILE_DIR"
echo "install dir: $FIREFOX_DIR"

echo "killing any running firefox and borealfox processes..."
pkill -f firefox || true
pkill -f borealfox-panel.py || true
fuser -k 8080/tcp 2>/dev/null || true
sleep 1

echo "installing user.js..."
cp "$REPO_DIR/patches/user.js" "$PROFILE_DIR/user.js"

echo "installing userChrome.css..."
mkdir -p "$PROFILE_DIR/chrome"
cp "$REPO_DIR/patches/userChrome.css" "$PROFILE_DIR/chrome/userChrome.css"
if [ -f "$REPO_DIR/patches/logo.png" ]; then
  cp "$REPO_DIR/patches/logo.png" "$PROFILE_DIR/chrome/logo.png"
fi

echo "installing extensions..."
mkdir -p "$PROFILE_DIR/extensions"
curl -sL "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi" -o "$PROFILE_DIR/extensions/uBlock0@raymondhill.net.xpi"
curl -sL "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi" -o "$PROFILE_DIR/extensions/{d7742d87-e61d-4b78-b8a1-b469842139fa}.xpi"
curl -sL "https://addons.mozilla.org/firefox/downloads/latest/localcdn-fork-of-decentraleyes/latest.xpi" -o "$PROFILE_DIR/extensions/{b86e4813-687a-43e6-ab65-0bde4ab75758}.xpi"
curl -sL "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi" -o "$PROFILE_DIR/extensions/addon@darkreader.org.xpi"
curl -sL "https://addons.mozilla.org/firefox/downloads/latest/matte-black-v1/latest.xpi" -o "$PROFILE_DIR/extensions/{f2b832a9-f0f5-4532-934c-74b25eb23fb9}.xpi"

echo "installing policies.json..."
sudo mkdir -p "$FIREFOX_DIR/distribution"
sudo cp "$REPO_DIR/distribution/policies.json" "$FIREFOX_DIR/distribution/policies.json"

echo "installing borealfox-settings launcher..."
LAUNCHER="/usr/local/bin/borealfox-settings"
printf '#!/bin/sh\nexec python3 "%s/patches/borealfox-panel.py"\n' "$REPO_DIR" | sudo tee "$LAUNCHER" >/dev/null
sudo chmod +x "$LAUNCHER"

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

echo "[ + ] done, launching borealfox settings..."
"$LAUNCHER" &
