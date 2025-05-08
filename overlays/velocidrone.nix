# overlay-velocidrone.nix  ── drop next to your flake, edit sha256 after first build
final: prev: {
  # brand-new attribute (no upstream package to override)
  velocidrone = final.stdenv.mkDerivation rec {
    name = "velocidrone";

    # Upstream requires login, but the link is stable enough for fetchzip
    # If the fetch fails, download manually, store next to this file and switch
    # to   url = "file://./velocidrone.zip";
    src = final.fetchzip {
      url = "https://www.velocidrone.com/download/launcher?id=debian";
      sha256 = final.lib.fakeSha256; # run once, copy the real hash
      stripRoot = false;
    };

    nativeBuildInputs = [
      final.unzip
      final.autoPatchelfHook
      final.makeWrapper
    ];
    buildInputs = [
      final.qt5.qtbase
      final.boost
    ];

    installPhase = ''
      mkdir -p $out/share/velocidrone
      cp -r * $out/share/velocidrone/

      mkdir -p $out/bin
      makeWrapper $out/share/velocidrone/Launcher $out/bin/velocidrone \
        --set-default LD_LIBRARY_PATH ${final.lib.makeLibraryPath buildInputs}
    '';

    meta = with final.lib; {
      description = "VelociDrone FPV drone-racing simulator";
      homepage = "https://www.velocidrone.com";
      license = licenses.unfree; # proprietary upstream :contentReference[oaicite:3]{index=3}
      maintainers = [maintainers.yourname];
      platforms = ["x86_64-linux"];
    };
  };
}
