#!/usr/bin/env bash

# Start Android emulator with software rendering
# This script starts the Pixel_7_API_36 emulator with software rendering (slower but stable)

echo "📱 Starting Android emulator with software rendering..."

# Check if ANDROID_HOME is set
if [ -z "$ANDROID_HOME" ]; then
    echo "❌ ANDROID_HOME is not set. Please run this from the nix development shell."
    exit 1
fi

# Start the emulator with software rendering
$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 -gpu off -no-snapshot
