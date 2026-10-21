{
  config,
  lib,
  localPackages,
  ...
}: {
  options.programs.quickshell.backgroundStyle = lib.mkOption {
    type = lib.types.enum ["macchiato" "liquid-glass"];
    description = ''
      Background material for the desktop bar and its panels: opaque dark
      Catppuccin Macchiato, or the Liquid Glass compositor effect.
    '';
  };
  options.programs.quickshell.phoneBatteryServiceUuid = lib.mkOption {
    type = lib.types.nullOr (lib.types.strMatching "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    default = null;
    description = "Public installation UUID displayed by the Battery Relay Android app; not a secret or authentication key.";
  };
  options.programs.quickshell.earbudsAccountKeyFile = lib.mkOption {
    type = lib.types.str;
    default = "${config.xdg.stateHome}/battery-relay/pixel-buds.account-key";
    description = "Runtime path to the private Fast Pair Account Key (0600). This is a string, never a Nix path or the key contents.";
  };
  options.programs.quickshell.earbudsBluetoothAddress = lib.mkOption {
    type = lib.types.nullOr (lib.types.strMatching "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}");
    default = null;
    description = "Public Bluetooth address of the earbuds, used only to identify their PC audio connection badge.";
  };

  config = {
    home.packages = with localPackages; [
      quickshellUpdateChecker
      quickshellUpdateDiff
      quickshellUpdateInstaller
      quickshellNixCleaner
      quickshellBrightness
      quickshellBeeper
      quickshellSystemStats
      quickshellGpuMonitor
      quickshellWeather
      quickshellSpeedtest
      batteryRelayReceiver
    ];

    programs.quickshell = {
      enable = true;
      # Choose "macchiato" for opaque dark backgrounds, or "liquid-glass".
      backgroundStyle = "macchiato";
      phoneBatteryServiceUuid = "e167a6ba-8246-4729-8ae6-4f1ecde39e1c";
      earbudsBluetoothAddress = "44:10:30:25:8F:4F";
      package = localPackages.quickshellRuntime;

      configs.top-bar = localPackages.quickshellDesktop;
      activeConfig = "top-bar";

      systemd = {
        enable = true;
        target = "graphical-session.target";
      };
    };

    # Live previews can temporarily point this generated config straight into
    # the store. Let activation reclaim this one path instead of treating the
    # preview symlink as an unmanaged file collision.
    xdg.configFile."quickshell/top-bar".force = true;

    # Qt otherwise selects the single-threaded basic render loop on this
    # NVIDIA/Wayland setup, making high-refresh QML animations visibly uneven.
    systemd.user.services.quickshell = {
      Unit = {
        X-Restart-Triggers = ["${localPackages.quickshellDesktop}"];
        # WantedBy starts the shell, but does not stop it at logout. Without
        # PartOf, it can survive `uwsm stop` connected to the old compositor,
        # and the next login sees an already-running (but invisible) service.
        PartOf = ["graphical-session.target"];
      };
      Service.Environment =
        [
          "QSG_RENDER_LOOP=threaded"
          "QS_PANEL_DIM_AMOUNT=${toString config.wayland.windowManager.hyprland.settings.config.decoration.dim_special}"
        ]
        ++ lib.optional (config.programs.quickshell.phoneBatteryServiceUuid != null)
        "QS_PHONE_BATTERY_SERVICE_UUID=${config.programs.quickshell.phoneBatteryServiceUuid}"
        ++ ["QS_EARBUDS_ACCOUNT_KEY_FILE=${config.programs.quickshell.earbudsAccountKeyFile}"]
        ++ lib.optional (config.programs.quickshell.earbudsBluetoothAddress != null)
        "QS_EARBUDS_BLUETOOTH_ADDRESS=${config.programs.quickshell.earbudsBluetoothAddress}";
    };
  };
}
