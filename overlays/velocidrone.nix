final: prev: {
  velocidrone = final.stdenv.mkDerivation rec {
    pname = "velocidrone";
    version = "1.17.1";
    src = ../material/velocidrone.zip; # local archive
    dontUnpack = true; # we unzip manually

    nativeBuildInputs = [
      final.unzip
      final.autoPatchelfHook
      final.wrapGAppsHook # ★ the magic wrapper
    ];

    buildInputs = [
      final.qt5.qtbase
      final.xkeyboard_config # /share/X11/xkb → fixes XKB lookup
      final.boost
      final.alsa-lib # Unity audio
      final.openal # fallback audio
      final.libpulseaudio # PulseAudio backend
      final.mesa # libGL & friends
      final.libudev-zero # udev symlink shim for old binaries
    ];

    installPhase = ''
      runHook preInstall
      unzip -qq $src
      chmod +x Launcher                # ZIP drops exec bit
      mkdir -p $out/bin
      mv Launcher $out/bin/velocidrone # hook will wrap this ELF
      cp -r *        $out/share/velocidrone
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
