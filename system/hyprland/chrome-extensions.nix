{
  # Install TabCtl from the Chrome Web Store. The matching native-messaging
  # host is managed in Home Manager, so no imperative `tabctl install` step is
  # required.
  environment.etc."opt/chrome/policies/managed/tabctl.json".text =
    builtins.toJSON {
      ExtensionSettings = {
        "baomblllgemcgbignhpbipgiofmjdhpn" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      };
    };
}
