# Gazelle-TUI NetworkManager TUI
#
# This package automatically tracks the latest version from GitHub.
# The src below is just a fallback - it gets overridden by the flake input.
#
# To update to the latest version, run:
#   nix flake update gazelle-tui
# or update all inputs:
#   nix flake update
# or use nh with automatic updates:
#   nh os switch --update
final: prev: {
  gazelle-tui = prev.stdenv.mkDerivation {
    pname = "gazelle-tui";
    version = "unstable";

    # Source will be overridden by flake input (see flake.nix)
    # This is just a fallback if the input is not available
    src = prev.fetchFromGitHub {
      owner = "Zeus-Deus";
      repo = "gazelle-tui";
      rev = "v1.7.2";
      hash = "sha256-LHXnYXkBskyrHZqcoRoOKfFIWRVSkg7pKaVNFFC9YCI=";
    };

    nativeBuildInputs = [
      prev.makeWrapper
      prev.python3
    ];

    buildInputs = [
      prev.python3
      prev.networkmanager
    ];

    propagatedBuildInputs = with prev.python3Packages; [
      textual
    ];

    dontBuild = true;

    postPatch = ''
es = [./gazelle-macchiato.patch];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      mkdir -p $out/share/gazelle-tui

      # Install Python modules
      cp app.py $out/share/gazelle-tui/
      cp network.py $out/share/gazelle-tui/

      # Create main executable
      cat > $out/bin/gazelle <<EOF
      #!${prev.python3}/bin/python3
      import sys
      sys.path.insert(0, "$out/share/gazelle-tui")
      from app import Gazelle

      if __name__ == "__main__":
          app = Gazelle()
          app.run()
      EOF
      chmod +x $out/bin/gazelle

      # Wrap with proper Python path and NetworkManager
      wrapProgram $out/bin/gazelle \
        --prefix PATH : ${prev.lib.makeBinPath [prev.networkmanager]} \
        --prefix PYTHONPATH : ${prev.python3.pkgs.makePythonPath (with prev.python3Packages; [textual])}

      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "A minimal NetworkManager TUI for Linux with complete 802.1X enterprise WiFi support";
      homepage = "https://github.com/Zeus-Deus/gazelle-tui";
      license = licenses.mit;
      maintainers = [];
      mainProgram = "gazelle";
      platforms = platforms.linux;
    };
  };
}
