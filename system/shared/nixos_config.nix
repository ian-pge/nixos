{
  system.stateVersion = "25.11";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    extra-substituters = ["https://cache.numtide.com"];
    extra-trusted-public-keys = ["niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="];

    # Enable trusted users for Nix docker container
    trusted-users = ["root" "ian"];
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Paris";

  users.users."ian" = {
    isNormalUser = true;
    password = "ian";
    extraGroups = ["wheel" "nix-users"]; # Enable ‘sudo’ for the user.
  };
}
