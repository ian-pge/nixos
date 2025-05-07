{
  services.mako = {
    # Enable the mako notification daemon
    enable = true; #
    settings = {
      # Styling and behavior settings
      font = "Ubuntu Nerd Font 15";
      background-color = "#181926";
      text-color = "#eed49f";
      border-color = "#ffcc33";
      border-radius = 10;
      border-size = 3;

      default-timeout = 10000;
      ignore-timeout = true;

      output = "eDP-1";

      # Pango‐markup format string: title in blue bold, then body
      format = "<span color=\"#eed49f\"><b>%s</b></span>\\n%b";
    };
  };
}
