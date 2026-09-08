{
  inputs,
  localPackages,
  ...
}: {
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs localPackages;};
    backupFileExtension = "backup";
    users = {
      "ian" = import ../home_manager;
    };
  };
}
