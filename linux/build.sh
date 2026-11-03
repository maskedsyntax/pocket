#!/usr/bin/env bash

set -e
cd "$(dirname "$0")"

echo "Setting up Pocket launcher..."

# Build project
echo "Building project..."
mkdir -p bin
make clean
make

# Confirm build
if [ -f bin/pocket ]; then
    echo "Build successful!"
else
    echo "Build failed!"
    exit 1
fi

echo "Installing Pocket..."
sudo install -m 755 bin/pocket /usr/local/bin/pocket

# Pocket stays resident after first launch so the hotkey opens it instantly.
# Start it in the background at login...
echo "Installing autostart entry..."
install -Dm 644 pocket-autostart.desktop "$HOME/.config/autostart/pocket.desktop"

# ...and restart any running instance so the new binary takes effect now.
pkill -x pocket 2>/dev/null || true
if [ -n "$DISPLAY" ]; then
    setsid pocket --background >/dev/null 2>&1 < /dev/null &
fi

echo "Done. Run with: pocket"
