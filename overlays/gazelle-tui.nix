{inputs}: final: prev: let
  src = inputs.gazelle-src; # flake = false input
  pythonEnv = prev.python3.withPackages (ps:
    with ps; [
      textual
      rich
      platformdirs
    ]);
in {
  gazelle-tui = prev.stdenv.mkDerivation {
    pname = "gazelle-tui";
    version = "unstable";
    src = src;

    nativeBuildInputs = [prev.makeWrapper];
    buildInputs = [pythonEnv prev.networkmanager];

    installPhase = ''
            runHook preInstall
            mkdir -p $out/share/gazelle $out/bin

            # Install sources
            cp -r app.py network.py gazelle $out/share/gazelle/

            # Install the upstream launcher if present; otherwise make a tiny one
            if [ -f ./gazelle ]; then
              cp ./gazelle $out/bin/gazelle
              chmod +x $out/bin/gazelle
            else
              cat > $out/bin/gazelle <<'EOS'
      #!/usr/bin/env bash
      exec python3 "$out/share/gazelle/app.py" "$@"
      EOS
              chmod +x $out/bin/gazelle
            fi

            # Fix shebangs and wrap so modules + nmcli are found
            patchShebangs $out/bin/gazelle
            wrapProgram $out/bin/gazelle \
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
