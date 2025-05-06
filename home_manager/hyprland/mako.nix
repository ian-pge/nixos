{
  services.mako = {
    # Enable the mako notification daemon
    enable = true; #
    settings = {
      # Styling and behavior settings
      font = "Ubuntu Nerd Font 15";
      backgroundColor = "#181926";
      textColor = "#eed49f";
      borderColor = "#ffcc33";
      borderRadius = 10;
      borderSize = 3;

      defaultTimeout = 10000;
      ignoreTimeout = true;

      output = "eDP-1";

      # Pango‐markup format string: title in blue bold, then body
      format = "<span color=\"#eed49f\"><b>%s</b></span>\\n%b";
    };
  };
}
