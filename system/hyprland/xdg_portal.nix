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
  # 2) wire the portal stack
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true; # force apps to use portals
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland # OpenURI, Screencast, etc.
      pkgs.xdg-desktop-portal-cosmic
    ];
    config.common = {
      default = ["cosmic" "hyprland"]; # first match wins
      "org.freedesktop.impl.portal.FileChooser" = ["cosmic"];
    };
  };
}
