final: prev: {
  velocidrone = final.stdenv.mkDerivation rec {
    pname = "velocidrone";
    version = "1.17.1";
    src = ../material/velocidrone.zip;
    dontUnpack = true;
    dontWrapQtApps = true; # we do it ourselves

    nativeBuildInputs = [
      final.unzip
      final.autoPatchelfHook
      final.makeWrapper
    ];
    buildInputs = [
      final.qt5.qtbase # Qt libraries (pulls in libxkbcommon)
      final.boost
      final.xkeyboard_config # keyboard-layout data ★
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/velocidrone
      unzip -qq $src -d $out/share/velocidrone
      chmod +x $out/share/velocidrone/Launcher

      makeWrapper $out/share/velocidrone/Launcher $out/bin/velocidrone \
        --set-default LD_LIBRARY_PATH ${final.lib.makeLibraryPath buildInputs} \
        --set QT_XKB_CONFIG_ROOT ${final.xkeyboard_config}/share/X11/xkb

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
