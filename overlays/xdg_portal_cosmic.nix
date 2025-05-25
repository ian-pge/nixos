final: prev: {
  xdg-desktop-portal-cosmic = prev.xdg-desktop-portal-cosmic.overrideAttrs (old: {
    cargoBuildFlags = old.cargoBuildFlags or [] ++ ["--no-default-features"];
  });
}
