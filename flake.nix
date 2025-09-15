{
  description = "Flutter development environment for musestruct";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        
        # Android SDK configuration
        android-sdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          platforms-android-33
          platforms-android-32
          emulator
          system-images-android-34-google-apis-x86-64
          system-images-android-33-google-apis-x86-64
        ]);

        # Flutter version - using stable channel
        flutter = pkgs.flutter;

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Flutter and Dart
            flutter
            dart

            # Android development
            android-sdk
            jdk17

            # Desktop development (Linux/GTK)
            pkg-config
            cmake
            ninja
            gtk3
            glib
            pcre
            util-linux
            libselinux
            libsepol
            libthai
            libdatrie
            xorg.libXdmcp
            xorg.libXtst
            libxkbcommon
            mesa
            fontconfig
            freetype
            dbus
            at-spi2-core
            clang
            sysprof
            
            # Additional development tools
            git
            curl
            unzip
            which
            gnused
            file
            
            # Chrome for web development and testing
            google-chrome
            
            # VS Code extensions and IDE support
            nodejs_20
            
            # Development utilities
            watchexec
            ripgrep
            fd
          ];

          shellHook = ''
            # Set up Android SDK
            export ANDROID_HOME="${android-sdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
            
            # Set up Java
            export JAVA_HOME="${pkgs.jdk17}"
            
            # Flutter configuration
            export FLUTTER_ROOT="${flutter}"
            export PATH="$FLUTTER_ROOT/bin:$PATH"
            
            # Desktop development
            export PKG_CONFIG_PATH="${pkgs.gtk3}/lib/pkgconfig:${pkgs.glib}/lib/pkgconfig:${pkgs.sysprof}/lib/pkgconfig:$PKG_CONFIG_PATH"
            
            # Chrome for web development
            export CHROME_EXECUTABLE="${pkgs.google-chrome}/bin/google-chrome-stable"
            
            echo "🚀 Flutter development environment activated!"
            echo ""
            echo "Available tools:"
            echo "  - Flutter SDK: $(flutter --version | head -n1)"
            echo "  - Dart SDK: $(dart --version)"
            echo "  - Android SDK: $ANDROID_HOME"
            echo "  - Java: $(java -version 2>&1 | head -n1)"
            echo ""
            echo "Getting started:"
            echo "  1. Run 'flutter doctor' to check your setup"
            echo "  2. Run 'flutter create .' to initialize a Flutter project"
            echo "  3. Run 'flutter run' to start development"
            echo ""
            echo "Platform support:"
            echo "  - Mobile: Android (SDK included)"
            echo "  - Desktop: Linux (GTK)"
            echo "  - Web: Chrome support included"
            echo ""
            
            # Run flutter doctor to show setup status
            if command -v flutter &> /dev/null; then
              echo "Flutter doctor output:"
              flutter doctor || true
            fi
          '';

          # Set environment variables for the shell
          ANDROID_HOME = "${android-sdk}/share/android-sdk";
          ANDROID_SDK_ROOT = "${android-sdk}/share/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
          FLUTTER_ROOT = "${flutter}";
          CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome-stable";
        };

        # Formatter for the flake
        formatter = pkgs.nixpkgs-fmt;
      });
}
