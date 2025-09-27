#!/usr/bin/env bash

# Start Android emulator in headless mode
# This script starts the Pixel_7_API_36 emulator without a window for headless testing

echo "📱 Starting Android emulator in headless mode..."

# Check if ANDROID_HOME is set
if [ -z "$ANDROID_HOME" ]; then
    echo "❌ ANDROID_HOME is not set. Please run this from the nix development shell."
    exit 1
fi

# Start the emulator in headless mode
$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 -gpu off -no-window -no-snapshot
