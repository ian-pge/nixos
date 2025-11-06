# overlays/gazelle-tui.nix
{inputs}: final: prev: let
  src = inputs.gazelle-src;
  pythonEnv = prev.python3.withPackages (ps: with ps; [textual rich platformdirs]);
in {
  gazelle-tui = prev.stdenv.mkDerivation {
    pname = "gazelle-tui";
    version = "unstable";
    src = src;

    nativeBuildInputs = [prev.makeWrapper];
    buildInputs = [pythonEnv prev.networkmanager];

    installPhase = ''
            runHook preInstall

            # App payload
            mkdir -p $out/share/gazelle $out/bin
            cp -r app.py network.py gazelle $out/share/gazelle/ || true

            # Launcher
            if [ -f ./gazelle ]; then
              cp ./gazelle $out/bin/gazelle
              chmod +x $out/bin/gazelle
            else
              cat > $out/bin/gazelle <<'EOS'
      #!/usr/bin/env bash
      exec __PY__ "$out/share/gazelle/app.py" "$@"
      EOS
              sed -i "s#__PY__#${pythonEnv}/bin/python#g" $out/bin/gazelle
              chmod +x $out/bin/gazelle
            fi

            patchShebangs $out/bin/gazelle

            # --- Theme: Catppuccin Macchiato (Sapphire) ---
            mkdir -p $out/etc/xdg/textual/themes
            cat > $out/etc/xdg/textual/themes/catppuccin-macchiato-sapphire.json <<'JSON'
      {
        "name": "catppuccin-macchiato-sapphire",
        "colors": {
          "background": "#24273A",
          "surface":    "#363A4F",
          "panel":      "#1E2030",
          "text":       "#CAD3F5",
          "foreground": "#CAD3F5",
          "muted":      "#6E738D",
          "accent":     "#7DC4E4",
          "primary":    "#8AADF4",
          "success":    "#A6DA95",
          "warning":    "#EED49F",
          "error":      "#ED8796",
          "boost":      "#F4DBD6"
        }
      }
      JSON

            # --- sitecustomize: register & select theme automatically ---
            cat > $out/share/gazelle/sitecustomize.py <<'PY'
      from __future__ import annotations
      import json, os
      from pathlib import Path

      def _find_theme_path():
          candidates = []
          xdg_home = os.environ.get("XDG_CONFIG_HOME")
          if xdg_home:
              candidates.append(Path(xdg_home) / "textual" / "themes" / "catppuccin-macchiato-sapphire.json")
          for base in os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(":"):
              candidates.append(Path(base) / "textual" / "themes" / "catppuccin-macchiato-sapphire.json")
          for p in candidates:
              if p.is_file():
                  return p
          return None

      def _load_theme_obj():
          try:
              from textual.theme import Theme
          except Exception:
              return None
          p = _find_theme_path()
          if not p:
              return None
          try:
              data = json.loads(p.read_text())
              c = data.get("colors", {})
              return Theme(
                  name=data.get("name", "catppuccin-macchiato-sapphire"),
                  primary=c.get("primary", "#8AADF4"),
                  secondary=c.get("secondary", c.get("accent", "#7DC4E4")),
                  accent=c.get("accent", "#7DC4E4"),
                  foreground=c.get("foreground", c.get("text", "#CAD3F5")),
                  background=c.get("background", "#24273A"),
                  success=c.get("success", "#A6DA95"),
                  warning=c.get("warning", "#EED49F"),
                  error=c.get("error", "#ED8796"),
                  dark=True,
              )
          except Exception:
              return None

      def _install():
          try:
              from textual.app import App
          except Exception:
              return
          theme_obj = _load_theme_obj()
          if theme_obj is None:
              return
          orig_init = App.__init__
          def _init(self, *a, **kw):
              orig_init(self, *a, **kw)
              try:
                reg = getattr(self, "register_theme", None) or getattr(self, "add_theme", None)
                if reg:
                    try: reg(theme_obj)
                    except Exception: pass
                mgr = getattr(self, "themes", None) or getattr(self, "theme_manager", None)
                if mgr:
                    add = getattr(mgr, "add", None) or getattr(mgr, "register", None)
                    if add:
                        try: add(theme_obj)
                        except Exception: pass
                if os.environ.get("TEXTUAL_THEME", "") in ("", theme_obj.name):
                    try: self.theme = theme_obj.name
                    except Exception: pass
              except Exception:
                  pass
          App.__init__ = _init

      _install()
      PY

            runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/gazelle \
        --prefix PATH : ${prev.lib.makeBinPath [pythonEnv prev.networkmanager]} \
        --prefix PYTHONPATH : "$out/share/gazelle" \
        --prefix XDG_CONFIG_DIRS : "$out/etc/xdg" \
        --set-default TEXTUAL_THEME catppuccin-macchiato-sapphire
    '';

    meta = with prev.lib; {
      description = "Minimal NetworkManager TUI with full 802.1X support";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "gazelle";
    };
  };
}
