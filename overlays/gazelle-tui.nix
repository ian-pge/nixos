{inputs}: final: prev: let
  src = inputs.gazelle-src; # flake = false
  pythonEnv = prev.python3.withPackages (ps: with ps; [textual rich platformdirs]);
in {
  gazelle-tui = prev.stdenv.mkDerivation {
    pname = "gazelle-tui";
    version = "unstable";
    src = src;

    nativeBuildInputs = [prev.makeWrapper];
    buildInputs = [pythonEnv prev.networkmanager];

    # NEW: append a Macchiato theme + register it on startup
    postPatch = ''
            cat >> app.py <<'PY'
      from textual.theme import Theme

      CATPPUCCIN_MACCHIATO = Theme(
          name="catppuccin-macchiato",
          # core Catppuccin Macchiato colors
          background="#24273a",  # base
          surface="#363a4f",     # surface0
          panel="#494d64",       # surface1
          foreground="#cad3f5",  # text
          primary="#b7bdf8",     # lavender
          secondary="#8aadf4",   # blue
          accent="#c6a0f6",      # mauve
          success="#a6da95",     # green
          warning="#eed49f",     # yellow
          error="#ed8796",       # red
          dark=True,
      )

      # Ensure the theme is available even before you pick it in the palette.
      try:
          _orig_on_mount = Gazelle.on_mount
          def _on_mount_with_theme(self, *a, **kw):
              self.register_theme(CATPPUCCIN_MACCHIATO)
              return _orig_on_mount(self, *a, **kw)
          Gazelle.on_mount = _on_mount_with_theme
      except Exception:
          # If class name or lifecycle changes upstream, we skip silently.
          pass
      PY
    '';

    installPhase = ''
            runHook preInstall
            mkdir -p $out/share/gazelle $out/bin
            cp -r app.py network.py gazelle $out/share/gazelle/

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

            patchShebangs $out/bin/gazelle
            wrapProgram $out/bin/gazelle \
              --set PYTHONPATH "$out/share/gazelle" \
              --prefix PATH : ${prev.lib.makeBinPath [prev.networkmanager]} \
              --set-default TEXTUAL_THEME catppuccin-macchiato
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
