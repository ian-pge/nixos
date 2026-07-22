{
  buildGoModule,
  lib,
  src,
}: let
  chromeManifest = builtins.fromJSON (
    builtins.readFile "${src}/extensions/chrome/manifest.json"
  );
in
  buildGoModule {
    pname = "tabctl";
    version = chromeManifest.version;

    inherit src;
    vendorHash = "sha256-oSt9bwhTf4EBeWhgb6sXvGJK7B75MGya4Gp2nMPqgDM=";

    subPackages = [
      "cmd/tabctl"
      "cmd/tabctl-mediator"
    ];

    ldflags = [
      "-s"
      "-w"
      "-X github.com/tabctl/tabctl/internal/config.Version=${chromeManifest.version}"
    ];

    meta = {
      description = "Control browser tabs from the command line";
      homepage = "https://github.com/slastra/tabctl";
      license = lib.licenses.mit;
      mainProgram = "tabctl";
      platforms = lib.platforms.linux;
    };
  }
