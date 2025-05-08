# overlays/velocidrone.nix
final: prev: {
  velocidrone = final.stdenv.mkDerivation rec {
    pname = "velocidrone";
    version = "1.17.1";

    # proprietary archive you downloaded once
    src = ../material/velocidrone.zip;
    dontUnpack = true;

    # ---- build tools ----
    nativeBuildInputs = [
      final.unzip
      final.autoPatchelfHook
      final.qt5.wrapQtAppsHook # ★ correct attribute path
    ];

    # ---- runtime libraries ----
    buildInputs = [
      final.qt5.qtbase # Qt core libs
      final.xkeyboard_config # /share/X11/xkb → fixes XKB error
      final.boost
      final.alsa-lib # ALSA backend for Unity
      final.openal # OpenAL fallback
      final.libpulseaudio # PulseAudio backend
      final.mesa # OpenGL drivers & libGL.so
      final.libudev-zero # shim for /run/udev
    ];

    installPhase = ''
      runHook preInstall
      unzip -qq $src
      chmod +x Launcher                    # ZIP loses exec bit

      mkdir -p $out/bin
      mkdir -p $out/share/velocidrone
      mv Launcher $out/bin/velocidrone     # hook wraps everything in $out/bin
      cp -r * $out/share/velocidrone

      runHook postInstall
    '';

    meta = with final.lib; {
      description = "VelociDrone FPV drone-racing simulator";
      homepage = "https://www.velocidrone.com";
      license = licenses.unfree;
      maintainers = [maintainers.yourname];
      platforms = ["x86_64-linux"];
    };
  };
}
