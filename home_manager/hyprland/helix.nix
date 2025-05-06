{
  pkgs,
  lib,
  ...
}: {
  programs.helix = {
    enable = true;

    ### Core editor settings -----------------------------------------------
    settings = {
      editor = {
        "color-modes" = true; # colour the mode indicator :contentReference[oaicite:0]{index=0}

        "cursor-shape" = {
          # mode-specific cursor :contentReference[oaicite:1]{index=1}
          normal = "block";
          insert = "bar";
          select = "underline";
        };
      };
    };

    ### Extra binary (optional) -------------------------------------------
    # package = pkgs.helix;  # uncomment to override with a pinned helix if desired :contentReference[oaicite:5]{index=5}
  };
}
