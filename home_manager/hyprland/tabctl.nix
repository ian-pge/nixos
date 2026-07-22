{
  inputs,
  pkgs,
  ...
}: let
  tabctl = pkgs.callPackage ../../packages/tabctl.nix {
    src = inputs.tabctl;
  };

  chromeTabs = pkgs.writeShellApplication {
    name = "quickshell-chrome-tabs";
    runtimeInputs = [
      tabctl
      pkgs.jq
    ];
    text = ''
      command="''${1:-}"
      case "$command" in
        list)
          if output="$(tabctl --format json list 2>&1)"; then
            jq -cn --argjson tabs "$output" '{ok: true, tabs: $tabs}'
          else
            jq -cn --arg error "$output" '{ok: false, tabs: [], error: $error}'
          fi
          ;;
        activate)
          tab_id="''${2:?missing tab id}"
          exec tabctl activate --focused "$tab_id"
          ;;
        close)
          tab_id="''${2:?missing tab id}"
          exec tabctl close "$tab_id"
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
