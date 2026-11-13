{
  config,
  lib,
  pkgs,
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
    # Chrome canonicalizes an unpacked extension's path. A real directory
    # keeps it stable across Nix generations, unlike a link into the store.
    home.activation.quickshellSpellingExtension = lib.hm.dag.entryAfter ["linkGeneration"] ''
      spellingDir=${lib.escapeShellArg "${config.xdg.dataHome}/quickshell-spelling-extension"}
      if [ -L "$spellingDir" ]; then run ${pkgs.coreutils}/bin/rm "$spellingDir"; fi
      run ${pkgs.coreutils}/bin/mkdir -p "$spellingDir"
      for spellingFile in manifest.json background.js editor.js content.js popup.html; do
        run ${pkgs.coreutils}/bin/install -m 644 "${localPackages.quickshellSpellingExtension}/extension/$spellingFile" "$spellingDir/$spellingFile"
      done
    '';
    xdg.configFile."google-chrome/NativeMessagingHosts/com.quickshell.spelling.json" = {
      source = "${localPackages.quickshellSpellingExtension}/native-messaging/com.quickshell.spelling.json";
      force = true;
    };
    # The local model for pi, used by the Qwen conversation of the bottom notch.
    # Thinking is switched from the chat (Ctrl+Tab): only off and high exist,
    # sent to Ollama as reasoning_effort "none" and "high".
    home.file.".pi/agent/models.json".text = builtins.toJSON {
      providers.ollama = {
        baseUrl = "http://127.0.0.1:11434/v1";
        api = "openai-completions";
        apiKey = "ollama";
        models = [
          {
            id = "huihui_ai/qwen3.5-abliterated:9b";
            name = "Qwen3.5 9B Abliterated";
            reasoning = true;
            thinkingLevelMap = {
              off = "none";
              minimal = null;
              low = null;
              medium = null;
              high = "high";
            };
            input = ["text"];
            contextWindow = 32768;
            # Reasoning and the answer share this budget.
            maxTokens = 16384;
          }
        ];
      };
    };
    home.packages = with localPackages; [
      quickshellUpdateChecker
      quickshellUpdateDiff
      quickshellUpdateInstaller
      quickshellNixCleaner
      quickshellBrightness
      quickshellBeeper
      quickshellAssistant
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
