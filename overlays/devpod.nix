# Correct structure: Takes final and prev as arguments directly
final: prev:
let
  # Define the desired version within the overlay's scope
  devpodVersion = "0.6.15";
in
{
  # Override the devpod package
  devpod = prev.devpod.overrideAttrs (oldAttrs: {
    version = devpodVersion; # Use the defined version variable
    src = final.fetchFromGitHub {
      owner = "loft-sh";
      repo  = "devpod";
      rev = "v${devpodVersion}"; # Use the defined version variable

      # !!! IMPORTANT !!!
      # Replace fakeSha256 with the actual hash.
      # You can get this by building once with fakeSha256,
      # Nix will error and tell you the expected hash.
      # sha256 = final.lib.fakeSha256;
      sha256 = "sha256-fLUJeEwNDyzMYUEYVQL9XGQv/VAxjH4IZ1SJa6jx4Mw="; # Replace this placeholder

    };

    # !!! IMPORTANT !!!
    # Replace fakeSha256 with the actual vendor hash.
    # Building will likely fail without the correct hash. Check the build logs.
    # vendorHash = final.lib.fakeSha256;
    vendorHash = null; # Replace this placeholder

    # Append to existing ldflags instead of replacing, if any exist
    ldflags = (oldAttrs.ldflags or []) ++ [
      "-X github.com/loft-sh/devpod/pkg/version.version=v${devpodVersion}" # Use the defined version variable
    ];

    # It's often good practice to preserve passthru and meta attributes
    passthru = oldAttrs.passthru or {};
    meta = oldAttrs.meta // {
      # Optionally update maintainers or description if desired
    };
  });
}
