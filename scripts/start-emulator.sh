#!/usr/bin/env bash

# Start Android emulator with hardware acceleration
# This script starts the Pixel_7_API_36 emulator with SwiftShader indirect rendering

echo "📱 Starting Android emulator with hardware acceleration..."

# Check if ANDROID_HOME is set
if [ -z "$ANDROID_HOME" ]; then
    echo "❌ ANDROID_HOME is not set. Please run this from the nix development shell."
    exit 1
fi

# Start the emulator
$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 -gpu swiftshader_indirect -no-snapshot -wipe-data
