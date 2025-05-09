{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    protonup-qt
    lutris
  ];
}
