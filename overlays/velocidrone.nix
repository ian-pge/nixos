# overlay-velocidrone.nix  ── drop next to your flake, edit sha256 after first build
final: prev: {
  velocidrone = final.stdenv.mkDerivation rec {
    pname = "velocidrone";
    version = "1.17.1"; # or leave unset – upstream bundles version

    src = final.fetchzip {
      # URL stays unchanged
      url = "file:///etc/nixos/material/velocidrone.zip";
      sha256 = "091w7nmsssfhyhgqi5i1ff7kgj65i1sf3zwvjsyc962wk2v5jcaj";
      stripRoot = false;

      # <-- the crucial line
      # extension = "zip"; # tell fetchzip “this really is a .zip”
      # (optionally) name  = "velocidrone-${version}.zip";
    };

    nativeBuildInputs = [final.unzip final.autoPatchelfHook final.makeWrapper];
    buildInputs = [final.qt5.qtbase final.boost];

    installPhase = ''
      mkdir -p $out/share/velocidrone
      cp -r * $out/share/velocidrone
      makeWrapper $out/share/velocidrone/Launcher $out/bin/velocidrone \
        --set-default LD_LIBRARY_PATH ${final.lib.makeLibraryPath buildInputs}
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
