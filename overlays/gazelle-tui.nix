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
    src = src;

    nativeBuildInputs = [prev.makeWrapper];
    buildInputs = [pythonEnv prev.networkmanager];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/gazelle $out/bin
      cp -r app.py network.py gazelle $out/share/gazelle/ || true
      # launcher
      makeWrapper ${pythonEnv.interpreter} $out/bin/gazelle \
        --add-flags "$out/share/gazelle/app.py" \
        --set PYTHONPATH "$out/share/gazelle" \
        --prefix PATH : ${prev.lib.makeBinPath [prev.networkmanager]}
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Minimal NetworkManager TUI with full 802.1X support";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "gazelle";
    };
  };
}
