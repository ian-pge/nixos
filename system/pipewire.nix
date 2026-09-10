{
  services.pipewire = {
    wireplumber.enable = true;
    wireplumber.extraConfig."10-output-priorities" = {
      "wireplumber.settings" = {
        # Do not restore past manual choices across sessions. The hotplug hook
        # below releases the current choice when device availability changes.
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
    wireplumber.extraScripts."default-nodes/release-on-hotplug.lua" =
      builtins.readFile ./wireplumber/release-on-hotplug.lua;
    wireplumber.extraConfig."11-release-on-hotplug" = {
      "wireplumber.components" = [
        {
          name = "default-nodes/release-on-hotplug.lua";
          type = "script/lua";
          provides = "custom.default-nodes.release-on-hotplug";
        }
      ];
      "wireplumber.profiles".main."custom.default-nodes.release-on-hotplug" = "required";
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
