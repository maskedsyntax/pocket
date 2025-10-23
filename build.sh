#!/usr/bin/env bash

set -e

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
