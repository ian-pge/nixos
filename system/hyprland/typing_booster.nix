{pkgs, ...}: {
  i18n.inputMethod = {
    enabled = "ibus"; # sur les versions récentes ça devient: type = "ibus"; enable = true;
    ibus.engines = with pkgs.ibus-engines; [
      typing-booster
    ];
  };
}
