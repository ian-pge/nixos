final: prev: {
  gazelle-tui = prev.python3Packages.buildPythonApplication rec {
    pname = "gazelle-tui";
    version = "1.7.2";

    src = prev.fetchFromGitHub {
      owner = "Zeus-Deus";
      repo = "gazelle-tui";
      rev = "v${version}";
      hash = "sha256-LHXnYXkBskyrHZqcoRoOKfFIWRVSkg7pKaVNFFC9YCI=";
    };

    propagatedBuildInputs = with prev.python3Packages; [
      textual
    ];

    nativeBuildInputs = [prev.makeWrapper];

    # Don't try to fetch dependencies from PyPI
    dontUsePipInstall = true;

    installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            mkdir -p $out/lib/python${prev.python3.pythonVersion}/site-packages/gazelle

            # Install Python modules
            cp app.py $out/lib/python${prev.python3.pythonVersion}/site-packages/gazelle/
            cp network.py $out/lib/python${prev.python3.pythonVersion}/site-packages/gazelle/
            touch $out/lib/python${prev.python3.pythonVersion}/site-packages/gazelle/__init__.py

            # Create wrapper script
            cat > $out/bin/gazelle <<EOF
      #!/usr/bin/env python3
      import sys
      sys.path.insert(0, "$out/lib/python${prev.python3.pythonVersion}/site-packages")
      from gazelle.app import main
      if __name__ == '__main__':
          main()
      EOF
            chmod +x $out/bin/gazelle

            # Wrap with NetworkManager in PATH
            wrapProgram $out/bin/gazelle \
              --prefix PATH : ${prev.lib.makeBinPath [prev.networkmanager]} \
              --prefix PYTHONPATH : "$out/lib/python${prev.python3.pythonVersion}/site-packages:$PYTHONPATH"

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
