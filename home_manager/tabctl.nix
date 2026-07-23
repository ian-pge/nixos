{
  inputs,
  pkgs,
  ...
}: let
  tabctl = pkgs.callPackage ../packages/tabctl.nix {
    src = inputs.tabctl;
  };

  chromeTabFavicons = pkgs.writeShellApplication {
    name = "quickshell-chrome-tab-favicons";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec python3 ${./quickshell/helpers/chrome-tab-favicons.py}
    '';
  };

  chromeTabs = pkgs.writeShellApplication {
    name = "quickshell-chrome-tabs";
    runtimeInputs = [
      tabctl
      chromeTabFavicons
      pkgs.jq
    ];
    text = ''
      command="''${1:-}"
      case "$command" in
        list)
          if output="$(tabctl --format json list 2>&1)"; then
            printf '%s' "$output" | quickshell-chrome-tab-favicons
          else
            error="''${output%%$'\n'*}"
            error="''${error#Error: }"
            jq -cn --arg error "$error" '{ok: false, tabs: [], error: $error}'
          fi
          ;;
        activate|close)
          tab_id="''${2:?missing tab id}"
          if [[ "$command" == "activate" ]]; then
            action=(tabctl activate --focused "$tab_id")
          else
            action=(tabctl close "$tab_id")
          fi
          if output="$("''${action[@]}" 2>&1)"; then
            jq -cn '{ok: true}'
          else
            error="''${output%%$'\n'*}"
            error="''${error#Error: }"
            jq -cn --arg error "$error" '{ok: false, error: $error}'
          fi
          ;;
        status)
          exec tabctl status
          ;;
        *)
          echo "usage: quickshell-chrome-tabs {list|activate|close|status} [tab-id]" >&2
          exit 2
          ;;
      esac
    '';
  };

  nativeMessagingHost = {
    name = "tabctl_mediator";
    description = "TabCtl Native Messaging Host";
    path = "${tabctl}/bin/tabctl-mediator";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://baomblllgemcgbignhpbipgiofmjdhpn/"
    ];
  };
in {
  home.packages = [
    tabctl
    chromeTabs
  ];

  xdg.configFile."google-chrome/NativeMessagingHosts/tabctl_mediator.json".text =
    builtins.toJSON nativeMessagingHost;
}
