{
  imports = [
    ./shared/system.nix
    ./hyprland/system_hyprland.nix
  ];

  # Define specializations
  specialisation = {
    gnome = {
      inheritParentConfig = false;
      configuration = {
        imports = [
          ./shared/system.nix
          ./gnome/system_gnome.nix
        ];
      };
    };
  };
}
