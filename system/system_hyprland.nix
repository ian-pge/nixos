{ config, pkgs, inputs, ... }:

{
    programs.fuse.userAllowOther = true;
    home-manager = {
        extraSpecialArgs = {inherit inputs;};
        backupFileExtension = "backup";
        users = {
        "ian" = import ../home_manager/home_hyprland.nix;
        };
    };

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # Packages
    environment.systemPackages = with pkgs; [
        hyprland
        kitty
        ly
    ];
}
