final: prev: let
  newVersion = "1.1.0";
in {
  xdg-desktop-portal-termfilechooser = prev.xdg-desktop-portal-termfilechooser.overrideAttrs (old: {
    pname = "xdg-desktop-portal-termfilechooser";
    version = newVersion;

    src = final.fetchFromGitHub {
      owner = "hunkyburrito";
      repo = "xdg-desktop-portal-termfilechooser";
      rev = "v${newVersion}";
      # First build with lib.fakeSha256, copy the hash Nix prints,
      # then replace the line below.
      hash = final.lib.fakeSha256;
    };

    # Meson / C project – nothing else to change.
    # Keep existing meta / passthru so the module still works.
  });
}
