#!/usr/bin/env bash

set -e

echo "Setting up Pocket launcher..."

# Build project
echo "Building project..."
mkdir -p bin

go build -o bin/pocket ./cmd/pocket


# Confirm build
if [ -f bin/pocket ]; then
    echo "Build successful!"
    cp ./bin/pocket ~/.local/bin/pocket
else
    echo "Build failed!"
    exit 1
fi
