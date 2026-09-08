{pkgs, ...}: {
  # Allow controlling external monitors through DDC/CI.
  hardware.i2c.enable = true;
  users.users."ian".extraGroups = ["i2c"];

  environment.systemPackages = [pkgs.ddcutil];
}
