{
  description = "Flutter development environment for musestruct";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };

        };

        buildToolsVersion = "35.0.0";
        cmakeVersion = "3.22.1";
        
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          buildToolsVersions = [ buildToolsVersion ];
          platformVersions = [ "36" "35" "34"];
          abiVersions = [ "armeabi-v7a" "arm64-v8a" "x86_64" ];
          systemImageTypes = [ "google_apis" "google_apis_playstore" ];
          includeEmulator = true;
          useGoogleAPIs = true;
          includeNDK = true;
          ndkVersions = [ "27.0.12077973" ];
          includeSystemImages = true;
          includeCmake = true;
          cmakeVersions = [ cmakeVersion ];
        };
        androidSdk = androidComposition.androidsdk;

        # Flutter version - using stable channel
        flutter = pkgs.flutter;

      in
      {
        devShells.default = pkgs.mkShell rec {
          buildInputs = with pkgs; [
            # Flutter and Dart
            flutter
            dart

            # Android development
            androidSdk
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
            
            # Additional libraries for Flutter plugins
            libsecret
            libsoup_3
            
            # Audio/video libraries for audioplayers plugin
            gst_all_1.gstreamer
            gst_all_1.gst-plugins-base
            gst_all_1.gst-plugins-good
            gst_all_1.gst-plugins-bad
            gst_all_1.gst-plugins-ugly
            gst_all_1.gst-libav
            pulseaudio
            alsa-lib
            
            # Additional development tools
            git
            curl
            unzip
            which
            gnused
            file
            
            # Rust development
            rustc
            cargo
            cargo-watch
            rustfmt
            clippy
            rust-analyzer
            
            # Chrome for web development and testing
            google-chrome
            
            # VS Code extensions and IDE support
            nodejs_20
            
            # Development utilities
            watchexec
            ripgrep
            fd
            
            # Docker and containerization
            docker-compose

            webkitgtk_4_1
          ];

          # Set environment variables for the shell
          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
          FLUTTER_ROOT = "${flutter}";
          CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome-stable";
          ANDROID_NDK_ROOT="$ANDROID_HOME/ndk-bundle";
          GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${ANDROID_HOME}/build-tools/${buildToolsVersion}/aapt2";

          shellHook = ''
            # Set up Android SDK
            export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            export PATH="$(echo "$ANDROID_HOME/cmake/${cmakeVersion}".*/bin):$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

            export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk-bundle";
            export GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${ANDROID_HOME}/build-tools/${buildToolsVersion}/aapt2";

            
            # Set up Java
            export JAVA_HOME="${pkgs.jdk17}"
            
            # Flutter configuration
            export FLUTTER_ROOT="${flutter}"
            export PATH="$FLUTTER_ROOT/bin:$PATH"
            
            # Desktop development
            export PKG_CONFIG_PATH="${pkgs.gtk3}/lib/pkgconfig:${pkgs.glib}/lib/pkgconfig:${pkgs.sysprof}/lib/pkgconfig:${pkgs.libsecret}/lib/pkgconfig:${pkgs.libsoup_3}/lib/pkgconfig:${pkgs.gst_all_1.gstreamer}/lib/pkgconfig:${pkgs.gst_all_1.gst-plugins-base}/lib/pkgconfig:${pkgs.pulseaudio}/lib/pkgconfig:${pkgs.alsa-lib}/lib/pkgconfig:$PKG_CONFIG_PATH"
            
            # Chrome for web development
            export CHROME_EXECUTABLE="${pkgs.google-chrome}/bin/google-chrome-stable"
            
            # Rust development aliases
            alias start-backend="docker-compose up -d postgres && cd backend && cargo watch -x run"
            alias stop-backend="docker-compose down && echo 'Backend and database stopped'"
            
            # Android emulator aliases
            alias start-emulator="$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 -gpu swiftshader_indirect -no-snapshot -wipe-data"
            alias start-emulator-software="$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 -gpu off -no-snapshot"
            alias start-emulator-headless="$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 -gpu off -no-window -no-snapshot"
            alias list-emulators="$ANDROID_HOME/emulator/emulator -list-avds"
            alias create-emulator="avdmanager create avd -n Pixel_7_API_36 -k 'system-images;android-36;google_apis;x86_64' -d 'pixel_7'"
            alias delete-emulator="$avdmanager delete avd -n Pixel_7_API_36"
            
            echo "🚀 Flutter development environment activated!"
            echo ""
            echo "Available tools:"
            echo "  - Flutter SDK: $(flutter --version | head -n1)"
            echo "  - Dart SDK: $(dart --version)"
            echo "  - Rust: $(rustc --version)"
            echo "  - Cargo: $(cargo --version)"
            echo "  - Android SDK: $ANDROID_HOME"
            echo "  - Java: $(java -version 2>&1 | head -n1)"
            echo ""
            echo "Getting started:"
            echo "  Flutter:"
            echo "    1. Run 'flutter doctor' to check your setup"
            echo "    2. Run 'flutter create .' to initialize a Flutter project"
            echo "    3. Run 'flutter run' to start development"
            echo ""
            echo "  Rust:"
            echo "    1. Run 'cargo new project_name' to create a new Rust project"
            echo "    2. Run 'start-backend' for hot-reload development in backend/ dir"
            echo "    3. Run 'cargo build' to build your project"
            echo ""
            echo "  Android Emulator:"
            echo "    1. Run 'create-emulator' to create a new Pixel 7 API 34 emulator"
            echo "    2. Run 'start-emulator' to start emulator with software rendering"
            echo "    3. Run 'start-emulator-software' for pure software rendering (slower but stable)"
            echo "    4. Run 'start-emulator-headless' for headless testing"
            echo "    5. Run 'list-emulators' to see available emulators"
            echo "    6. Run 'delete-emulator' to delete the Pixel_7_API_36 emulator"
            echo ""
            echo "Platform support:"
            echo "  - Mobile: Android (SDK included)"
            echo "  - Desktop: Linux (GTK)"
            echo "  - Web: Chrome support included"
            echo "  - Rust: Full toolchain with cargo, rustfmt, clippy, and rust-analyzer"
            echo ""
            
            # Run flutter doctor to show setup status
            if command -v flutter &> /dev/null; then
              echo "Flutter doctor output:"
              flutter doctor || true
            fi
          '';

          
        };

        # Formatter for the flake
        formatter = pkgs.nixpkgs-fmt;
      });
}
