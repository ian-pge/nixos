{
  imports = [
    ./system/shared/system_shared.nix
    ./hyprland/system_hyprland.nix
  ];

  # Define specializations
  specialisation = {
    gnome = {
      inheritParentConfig = false;
      configuration = {
        imports = [
          ./system/shared/system_shared.nix
          ./gnome/system_gnome.nix
        ];
      };
    };
  };
}
