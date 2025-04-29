{
  services.mako = {
    # Enable the mako notification daemon
    enable = true; #

    # Styling and behavior settings
    font = "Ubuntu Nerd Font 15";
    backgroundColor = "#181926";
    textColor = "#eed49f";
    borderColor = "#ffcc33";
    borderRadius = "8";

    # Timeout in milliseconds (0 = no timeout)
    defaultTimeout = "5000";

    # Show notifications on a specific Wayland output
    output = "eDP-1";

    # Pango‐markup format string: title in blue bold, then body
    format = "<span color=\"#eed49f\"><b>%s</b></span>\n%b";
  };
}
