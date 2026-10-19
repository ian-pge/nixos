{pkgs}: let
  android = (pkgs.androidenv.override {licenseAccepted = true;}).composeAndroidPackages {
    platformVersions = ["36"];
    buildToolsVersions = ["35.0.0"];
    toolsVersion = null;
    includeEmulator = false;
    includeSystemImages = false;
    includeNDK = false;
    includeSources = false;
    includeCmake = false;
  };
  sdk = "${android.androidsdk}/libexec/android-sdk";
in
  pkgs.mkShell {
    packages = [
      pkgs.jdk17
      android.androidsdk
      (pkgs.gradle_8.override {java = pkgs.jdk17;})
    ];

    JAVA_HOME = "${pkgs.jdk17}";
    ANDROID_HOME = sdk;
    ANDROID_SDK_ROOT = sdk;
    # Use Nix's patched native binary, not the incompatible Maven ELF on NixOS.
    GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdk}/build-tools/35.0.0/aapt2";
    shellHook = ''
      export GRADLE_USER_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}/gradle"
    '';
  }
