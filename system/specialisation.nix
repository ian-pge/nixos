{ pkgs, ... }:

{
    imports =
    [
        ./system.nix
        ./system_hyprland.nix
    ];

    # HYPRLAND -----------------------------------------------
    system.nixos.tags = [ "hyprland" ];
    programs.hyprland.enable = true;
        xdg.portal = {
            enable = true;
            extraPortals = [
            pkgs.xdg-desktop-portal-gtk
            pkgs.xdg-desktop-portal-hyprland
            ];
        };
        # You might want a display manager for Hyprland
        services.displayManager.ly.enable = true;

    # GNOME -----------------------------------------------

    # Define specializations
    specialisation = {
        gnome = {
            inheritParentConfig = false;
            configuration = {
                imports = [
                    ./system.nix
                    ./system_gnome.nix
                ];
                # programs.dconf.enable = true;
                # services.xserver = {
                #     enable = true;
                #     displayManager.gdm.enable = true;
                #     desktopManager.gnome.enable = true;
                # };
                services.desktopManager.cosmic.enable = true;  # Turn on the COSMIC session
                services.displayManager.cosmic-greeter.enable = true;  # Use the COSMIC greeter
            };
        };
    };
}
