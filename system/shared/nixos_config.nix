{
  system.stateVersion = "24.11";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Paris";

  users.users."ian" = {
    isNormalUser = true;
    initialPassword = "ianbage";
    extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.
  };
}
