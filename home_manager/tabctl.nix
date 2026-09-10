{localPackages, ...}: let
  nativeMessagingHost = {
    name = "tabctl_mediator";
    description = "TabCtl Native Messaging Host";
    path = "${localPackages.tabctl}/bin/tabctl-mediator";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://baomblllgemcgbignhpbipgiofmjdhpn/"
    ];
  };
in {
  home.packages = [
    localPackages.tabctl
    localPackages.quickshellChromeTabs
  ];

  xdg.configFile."google-chrome/NativeMessagingHosts/tabctl_mediator.json".text =
    builtins.toJSON nativeMessagingHost;
}
