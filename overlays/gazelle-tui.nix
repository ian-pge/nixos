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
            # Add Catppuccin Macchiato with green accent theme
            cat > patch_theme.py << 'EOF'
      import re

      with open('app.py', 'r') as f:
          content = f.read()

      # Build theme code with proper indentation (8 spaces for the method level)
      theme_lines = [
          "        # Register Catppuccin Macchiato with green accent",
          "        self.register_theme(",
          "            Theme(",
          '                name="catppuccin-macchiato-green",',
          '                primary="#a6da95",      # Catppuccin Macchiato Green',
          '                secondary="#a6da95",',
          '                accent="#a6da95",',
          '                foreground="#cad3f5",   # Catppuccin Macchiato Text',
          '                background="#24273a",   # Catppuccin Macchiato Base',
          '                surface="#24273a",',
          '                panel="#24273a",',
          '                dark=True,',
          "            )",
          "        )",
      ]
      theme_code = "\n".join(theme_lines)

      # Find the line AFTER the entire if/else block (the "Load saved theme" comment)
      # and insert our theme registration before it
      pattern = r'(        # Load saved theme or use default\n)'
      replacement = theme_code + '\n\n' + r'\1'
      content = re.sub(pattern, replacement, content)

      with open('app.py', 'w') as f:
          f.write(content)
      EOF
            ${prev.python3}/bin/python3 patch_theme.py
    '';

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
