{
  imports = [
    ./system.nix
    ./system_hyprland.nix
  ];

  # Define specializations
  specialisation = {
    gnome = {
      inheritParentConfig = false;
      configuration = {
        imports = [
          ./system.nix
          ./system_gnome.nix
        ];
      };
    };
  };
}
