# overlays/velocidrone.nix
final: prev: {
  velocidrone = final.stdenv.mkDerivation rec {
    pname = "velocidrone";
    version = "1.17.1";
    src = ../material/velocidrone.zip;
    dontUnpack = true;

    nativeBuildInputs = [
      final.unzip
      final.autoPatchelfHook
      final.qt5.wrapQtAppsHook # wraps every ELF in $out/bin
    ];

    buildInputs = [
      final.qt5.qtbase
      final.xkeyboard_config # XKB data  ★
      final.boost
      final.alsa-lib # Unity audio back-end
      final.openal
      final.libpulseaudio
      final.mesa # libGL / libxcb-glx
      final.libudev-zero # shim for old libudev
    ];

    ### tell the hook to add QT_XKB_CONFIG_ROOT
    qtWrapperArgs = [
      "--prefix"
      "QT_XKB_CONFIG_ROOT"
      ":"
      "${final.xkeyboard_config}/share/X11/xkb"
    ];

    installPhase = ''
      runHook preInstall
      unzip -qq $src
      chmod +x Launcher

      mkdir -p $out/bin
      mkdir -p $out/share/velocidrone
      mv Launcher $out/bin/velocidrone      # hook will wrap this script
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
