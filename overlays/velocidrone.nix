final: prev: {
  velocidrone = final.stdenv.mkDerivation rec {
    pname = "velocidrone";
    version = "1.17.1";

    # 1. local archive that you saved next to the overlay (relative path!)
    src = ./velocidrone.zip;

    # 2. tell the generic builder there is nothing to unpack automatically
    dontUnpack = true;

    nativeBuildInputs = [
      final.unzip
      final.autoPatchelfHook
      final.makeWrapper
    ];
    buildInputs = [
      final.qt5.qtbase # runtime Qt libs
      final.boost
    ];

    # 3. silence qtPreHook because we do our own wrapping below
    dontWrapQtApps = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/velocidrone
      unzip -qq $src -d $out/share/velocidrone

      makeWrapper $out/share/velocidrone/Launcher $out/bin/velocidrone \
        --set-default LD_LIBRARY_PATH ${final.lib.makeLibraryPath buildInputs}

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
