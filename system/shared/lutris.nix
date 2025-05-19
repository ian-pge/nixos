{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    lutris
    protonup-qt
    hello
    # wine
  ];
}
