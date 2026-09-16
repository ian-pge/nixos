{pkgs}: let
  # Official Lafayette 0.9 symbols, pinned so rebuilds keep the same layout.
  symbols = pkgs.fetchurl {
    url = "https://qwerty-lafayette.org/releases/lafayette_linux_v0.9.xkb_custom";
    sha256 = "0ihl39180bxqvd695dff46qqndqrv1z1lcqd7qbznr8fkbrz26ci";
  };
in
  pkgs.runCommand "lafayette-0.9.xkb" {
    nativeBuildInputs = [pkgs.libxkbcommon];
  } ''
    mkdir -p xkb/symbols
    cp ${symbols} xkb/symbols/lafayette
    xkbcli compile-keymap --include "$PWD/xkb" --include-defaults \
      --layout lafayette --variant lafayette --options compose:caps \
      --output-format 1 > "$out"
  ''
