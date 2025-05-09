{
  services.udev.extraRules = ''${builtins.readFile ../../material/betaflight.rules}'';

  users.users."ian".extraGroups = ["dialout"];
}
