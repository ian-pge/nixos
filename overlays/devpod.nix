# overlays/devpod.nix
{ lib, fetchFromGitHub, ...}:

self: super: {
  devpod = super.buildGoModule rec {
    pname = "devpod";
    version = "0.6.15";

    # Pull the exact v0.6.15 tag
    src = fetchFromGitHub {
      owner = "loft-sh";
      repo  = "devpod";
      rev   = "v${version}";
      sha256 = lib.fetchTarball { url = "https://example.com/fake"; };
    };

    # vendored Go modules—same deal with the hash
    vendorSha256 = lib.fetchTarball { url = "https://example.com/fake"; };

    # ensure both CLI and any subpackages build
    subPackages = [ "." ];

    meta = with super.lib; {
      description = "Client‑only dev environments (open‑source Codespaces)";
      homepage    = "https://devpod.sh";
      license     = licenses.mpl20;
      maintainers = with maintainers; [ maxbrunet ];
    };
  };
}
