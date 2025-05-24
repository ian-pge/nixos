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
  ############################################
  ## 1. install the backend                 ##
  ############################################
  environment.systemPackages = with pkgs; [
    cosmic-files # the GUI file manager
    xdg-desktop-portal-cosmic # the portal backend (MUST be present)
  ];

  ############################################
  ## 2. aggregate all portals               ##
  ############################################
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true; # make GTK/Qt ask the portal

    ## tell the aggregator which back-ends exist
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland # compositor bridge
      pkgs.xdg-desktop-portal-cosmic # new file chooser
    ];

    ## quickest way: reuse the config shipped by COSMIC
    # configPackages = [pkgs.xdg-desktop-portal-cosmic];

    ## equivalent fully-inline variant (uncomment if you dislike the above)
    config.hyprland = {
      fileChooser = ["cosmic"]; # try COSMIC first, fall back to GTK
    };
    config.default = ["hyprland" "cosmic"];
  };
}
