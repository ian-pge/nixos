# Correct structure: Takes final and prev as arguments directly
final: prev:
let
  # Define the desired version within the overlay's scope
  zedVersion = "0.183.11";
in
{
  # Override the zed package
  zed = prev.zed-editor.overrideAttrs (oldAttrs: {
    version = zedVersion; # Use the defined version variable
    src = final.fetchFromGitHub {
      owner = "zed-industries";
      repo  = "zed";
      rev = "v${zedVersion}"; # Use the defined version variable

      # !!! IMPORTANT !!!
      # Replace fakeSha256 with the actual hash.
      # You can get this by building once with fakeSha256,
      # Nix will error and tell you the expected hash.
      # sha256 = final.lib.fakeSha256;
      sha256 = "sha256-fLUJeEwNDyzMYUEYVQL9XGQv/VAxjH4IZ1SJ00000000"; # Replace this placeholder

    };

    # !!! IMPORTANT !!!
    # Replace fakeSha256 with the actual vendor hash.
    # Building will likely fail without the correct hash. Check the build logs.
    vendorHash = "sha256-fLUJeEwNDyzMYUEYVQL9XGQv/VAxjH4IZ1SJ00000000"; # Replace this placeholder
    # vendorHash = null; # Replace this placeholder

    # Append to existing ldflags instead of replacing, if any exist
    ldflags = (oldAttrs.ldflags or []) ++ [
      "-X github.com/zed-industries/zed/pkg/version.version=v${zedVersion}" # Use the defined version variable
    ];

    # It's often good practice to preserve passthru and meta attributes
    passthru = oldAttrs.passthru or {};
    meta = oldAttrs.meta // {
      # Optionally update maintainers or description if desired
    };
  });
}
