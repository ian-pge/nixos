# overlays/gazelle-tui.nix
{inputs}: final: prev: let
  src = inputs.gazelle-src;
  pythonEnv = prev.python3.withPackages (ps:
    with ps; [
      textual
      rich
      platformdirs
    ]);
in {
  gazelle-tui = prev.stdenv.mkDerivation {
    pname = "gazelle-tui";
    version = "unstable-" + (src.shortRev or "dev");

    # plain source, not a flake
    src = src;

    nativeBuildInputs = [prev.makeWrapper];
    buildInputs = [pythonEnv prev.networkmanager];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/gazelle $out/bin
      cp -r app.py network.py gazelle $out/share/gazelle/ || true
      makeWrapper ${pythonEnv.interpreter} $out/bin/gazelle \
        --add-flags "$out/share/gazelle/app.py" \
        --set PYTHONPATH "$out/share/gazelle" \
        --prefix PATH : ${prev.lib.makeBinPath [prev.networkmanager]}
      runHook postInstall
    '';
  };
}
