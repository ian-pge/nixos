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
            configuration = { inputs, ... }: {
                imports = [
                    inputs.disko.nixosModules.default
                    (import ./disko.nix { device = "/dev/nvme0n1"; })
                    inputs.impermanence.nixosModules.impermanence
                    inputs.home-manager.nixosModules.default
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
