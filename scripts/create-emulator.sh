#!/usr/bin/env bash

# Create a new Android emulator
# This script creates a new Pixel_7_API_36 emulator with the specified system image

echo "📱 Creating new Android emulator..."

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

# Create the emulator
echo "Creating Pixel_7_API_36 emulator..."
avdmanager create avd -n Pixel_7_API_36 -k 'system-images;android-36;google_apis;x86_64' -d 'pixel_7'

echo "✅ Emulator created successfully!"
echo "You can now start it with: ./scripts/start-emulator.sh"
