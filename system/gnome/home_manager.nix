{inputs, ...}: {
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "backup";
    users = {
      "ian" = import ../../home_manager/gnome;
    };
  };
}
