{
  imports = [./quickshell/helpers];

  programs.quickshell = {
    enable = true;

    configs.top-bar = ./quickshell/top-bar;
    activeConfig = "top-bar";

    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
  };
}
