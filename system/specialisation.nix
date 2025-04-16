{
    imports =
    [
        ./system.nix
        ./system_hyprland.nix
    ];

    # Define specializations
    specialisation = {
        gnome = {
            inheritParentConfig = false;
            configuration = {
                imports =
                [
                    ./system.nix
                    ./system_gnome.nix
                ];
                programs.dconf.enable = true;
                services.xserver = {
                    enable = true;
                    displayManager.gdm.enable = true;
                    desktopManager.gnome.enable = true;
                };
            };
        };
    };
}
