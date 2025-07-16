final: prev: {
  clisp = prev.clisp.overrideAttrs (old: {
    pname = "xdg-desktop-portal-termfilechooser";
    version = "2.49";
    src = prev.fetchurl {
      url = "https://ftp.gnu.org/gnu/clisp/release/2.49/clisp-2.49.tar.bz2";
      sha256 = "";
    };
    readline = prev.readline6;
  });
}
