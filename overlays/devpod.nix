# overlays/devpod.nix
final: prev:
let
  # pick whatever tag you like; 0.6.x is the current stable line
  version = "0.6.15";
in {
  devpod = prev.devpod.overrideAttrs (old: rec {
    inherit version;
    src = prev.fetchFromGitHub {
      owner = "loft-sh";
      repo  = "devpod";
      rev   = "v${version}";
      # first run with lib.fakeSha256, copy the hash from the
      # build error and replace it here.
      sha256 = "0000000000000000000000000000000000000000000000000000";
    };

    # `buildGoModule` now vendor‑hashes the Go modules
    vendorHash = "0000000000000000000000000000000000000000000000000000";

    # keep upstream’s hard‑coded linker flag in sync
    ldflags = [
      "-X github.com/loft-sh/devpod/pkg/version.version=v${version}"
    ];
  });

  # Optional: if you also want the Desktop app, repeat the pattern
  # for `devpod-desktop` or just remove it from `environment.systemPackages`.
}
