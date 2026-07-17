{ config, ... }:
{
  programs.vicinae = {
    enable = true;

    systemd = {
      enable = true;
      autoStart = true;
    };

    enableFirefoxIntegration = false;

    extensions = [
      (config.lib.vicinae.mkExtension {
        name = "runpod-manager";
        src = ./vicinae-extensions/runpod-manager;
      })
    ];

    settings = {
      # Always start from the root instead of restoring the previous view.
      pop_to_root_on_close = true;

      font = {
        rendering = "native";
        normal = {
          family = "Ubuntu Nerd Font";
          size = 12.0;
        };
      };

      theme.dark = {
        name = "catppuccin-macchiato-electric";
        icon_theme = "Papirus-Dark";
      };

      launcher_window = {
        opacity = 1.0;

        client_side_decorations = {
          enabled = true;
          border_width = 3;
          shadow_size = 0;
        };

        compact_mode.enabled = false;

        layer_shell = {
          enabled = true;
          keyboard_interactivity = "on_demand";
          layer = "top";
        };
      };
    };

    themes.catppuccin-macchiato-electric = {
      meta = {
        version = 1;
        name = "Catppuccin Macchiato Electric";
        description = "Catppuccin Macchiato with the electric-blue Fuzzel border.";
        variant = "dark";
        inherits = "catppuccin-macchiato";
      };

      colors = {
        core.border = "#33CCFF";
        main_window.border = "#33CCFF";
        settings_window.border = "#33CCFF";
      };
    };
  };

  # NixOS does not install Vicinae's Chromium native-messaging manifest.
  # Chrome uses this host to bridge the extension to the Vicinae daemon.
  xdg.configFile =
    let
      nativeMessagingHost.text = builtins.toJSON {
        name = "com.vicinae.vicinae";
        description = "Vicinae Native Messaging Host";
        path = "${config.programs.vicinae.package}/libexec/vicinae/vicinae-browser-link";
        type = "stdio";
        allowed_origins = [ "chrome-extension://kcmipingpfbohfjckomimmahknoddnke/" ];
      };
    in
    {
      "google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json" = nativeMessagingHost;
      "chromium/NativeMessagingHosts/com.vicinae.vicinae.json" = nativeMessagingHost;
    };
}
