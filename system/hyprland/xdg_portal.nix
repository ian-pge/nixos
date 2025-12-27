# {pkgs, ...}: {
#   # xdg.portal = {
#   #   enable = true;
#   #   extraPortals = with pkgs; [
#   #     # xdg-desktop-portal-termfilechooser
#   #     xdg-desktop-portal-cosmic
#   #   ];
#   #   config.common = {
#   #     # "org.freedesktop.impl.portal.FileChooser" = ["termfilechooser"];
#   #     "org.freedesktop.impl.portal.FileChooser" = ["cosmic"];
#   #   };
#   # };
#   environment.systemPackages = with pkgs; [
#     cosmic-files # the file manager itself
#   ];
#   xdg.portal = {
#     xdgOpenUsePortal = true;
#     enable = true;
#     # wlr.enable = true;
#     # lxqt.enable = true;
#     extraPortals = [
#       pkgs.xdg-desktop-portal-hyprland
#       pkgs.xdg-desktop-portal-cosmic
#     ];
#     config.common = {
#       default = ["hyprland"];
#       "org.freedesktop.impl.portal.FileChooser" = ["cosmic"];
#     };
#   };
# }
#
{pkgs, ...}: {
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-cosmic
      pkgs.xdg-desktop-portal-gtk
    ];

    config = {
      # This is the important part: per-desktop config for Hyprland
      hyprland = {
        default = ["hyprland" "gtk" "cosmic"];

        # Force screencast to XDPH (what you already fixed)
        "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
        "org.freedesktop.impl.portal.RemoteDesktop" = ["hyprland"];

        # Force file chooser to COSMIC
        "org.freedesktop.impl.portal.FileChooser" = ["cosmic"];
      };
    };
  };
}
