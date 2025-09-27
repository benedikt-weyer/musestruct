#!/usr/bin/env bash

# Delete Android emulator
# This script deletes the Pixel_7_API_36 emulator

echo "📱 Deleting Android emulator..."

# Check if ANDROID_HOME is set
if [ -z "$ANDROID_HOME" ]; then
    echo "❌ ANDROID_HOME is not set. Please run this from the nix development shell."
    exit 1
fi

# Check if avdmanager is available
if ! command -v avdmanager &> /dev/null; then
    echo "❌ avdmanager not found. Please ensure Android SDK is properly set up."
    exit 1
fi

# Delete the emulator
echo "Deleting Pixel_7_API_36 emulator..."
avdmanager delete avd -n Pixel_7_API_36

echo "✅ Emulator deleted successfully!"
