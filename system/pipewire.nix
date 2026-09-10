{
  services.pipewire = {
    wireplumber.enable = true;
    wireplumber.extraConfig."10-output-priorities" = {
      "wireplumber.settings" = {
        # Always select the best currently available output instead of
        # restoring a previously selected one.
        "node.restore-default-targets" = false;
      };

      # Internal speakers keep their default priority of 1000.
      "monitor.alsa.rules" = [
        {
          matches = [
            {"node.name" = "~alsa_output.*hdmi.*";}
          ];
          actions.update-props."priority.session" = 1100;
        }
        {
          matches = [
            {"node.name" = "~alsa_output.*Headphones.*";}
          ];
          actions.update-props."priority.session" = 1300;
        }
      ];

      "monitor.bluez.rules" = [
        {
          matches = [
            {"node.name" = "~bluez_output.*";}
          ];
          actions.update-props."priority.session" = 1200;
        }
      ];
    };
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    jack.enable = true;
  };
}
