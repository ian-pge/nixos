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

    postPatch = ''
        cat >> app.py <<'PY'
      # --- Begin injected Catppuccin Macchiato theme registration ---
      try:
          import inspect
          from textual.theme import Theme

          CATPPUCCIN_MACCHIATO = Theme(
              name="catppuccin-macchiato",
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

          def _wrap_register_theme(cls, method_name: str):
              if not hasattr(cls, method_name):
                  return
              orig = getattr(cls, method_name)

              def wrapper(self, *a, **kw):
                  # Make the theme available before the original hook runs
                  try:
                      self.register_theme(CATPPUCCIN_MACCHIATO)
                  except Exception:
                      pass

                  # Call original method with a signature-compatible call
                  try:
                      return orig(self, *a, **kw)  # if it accepts (event)
                  except TypeError:
                      return orig(self)            # if it's a no-arg handler

              setattr(cls, method_name, wrapper)

          # Prefer earlier hook; fall back if not present.
          try:
              _wrap_register_theme(Gazelle, "on_load")
          except Exception:
              pass
          try:
              _wrap_register_theme(Gazelle, "on_mount")
          except Exception:
              pass
      except Exception:
          # If Textual or Gazelle internals change, fail soft.
          pass
      # --- End injected Catppuccin Macchiato theme registration ---
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
