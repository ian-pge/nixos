{
  services.udev.extraRules = ''${builtins.readFile ../../material/99-slabs.rules}'';
  users.users."ian".extraGroups = ["video"];
}
