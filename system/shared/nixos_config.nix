{
  system.stateVersion = "25.11";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Enable trusted users for Nix docker container
  nix.settings.trusted-users = ["root" "ian"];

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Paris";

  users.users."ian" = {
    isNormalUser = true;
    initialPassword = "1234";
    extraGroups = ["wheel" "nix-users"]; # Enable ‘sudo’ for the user.
  };
}
