#!/usr/bin/env bash

# List available Android emulators
# This script lists all available Android Virtual Devices (AVDs)

echo "📱 Listing available Android emulators..."

# Check if ANDROID_HOME is set
if [ -z "$ANDROID_HOME" ]; then
    echo "❌ ANDROID_HOME is not set. Please run this from the nix development shell."
    exit 1
fi

# List available emulators
$ANDROID_HOME/emulator/emulator -list-avds
