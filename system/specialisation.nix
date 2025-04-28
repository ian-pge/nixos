{
  imports = [
    ./shared
    ./hyprland
  ];

  # Define specializations
  specialisation = {
    gnome = {
      inheritParentConfig = false;
      configuration = {
        imports = [
          ./shared
          ./gnome
        ];
      };
    };
  };
}
