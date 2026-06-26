#!/bin/sh
set -e

echo "all bookmarks, history, passwords, and settings will be wiped"
printf "are you sure? [y/N]: "
read answer
if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "aborted"
    exit 0
fi

echo ""
echo "killing firefox and borealfox..."
pkill -f firefox || true
pkill -f borealfox-panel.py || true
fuser -k 8080/tcp 2>/dev/null || true
sleep 1

echo "removing profile data..."
rm -rf "$HOME/.mozilla/firefox"
rm -rf "$HOME/.config/mozilla/firefox"

echo "removing global policies and borealfox-settings..."
sudo rm -f /usr/local/bin/borealfox-settings
sudo rm -f /usr/lib/firefox/distribution/policies.json
sudo rm -f /usr/lib64/firefox/distribution/policies.json
sudo rm -f /opt/firefox/distribution/policies.json
sudo rm -f /usr/share/firefox/distribution/policies.json
sudo rm -f /usr/bin/distribution/policies.json
sudo rm -f /etc/firefox/policies/policies.json
sudo rm -rf /usr/bin/distribution

echo "borealfox has been uninstalled"
