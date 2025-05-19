{pkgs, ...}: {
  home.packages = with pkgs; [
    clang-tools
    package-version-server
    nil
    nixd
    nixpkgs-fmt
    alejandra

    zed-editor
    devpod
    bambu-studio
    google-chrome
    blender
    davinci-resolve
    nvd
    nix-output-monitor
    zotero
    neofetch
    obsidian
    freecad-wayland
    # firefox
    gyroflow
    wget
    pika-backup
    inkscape
  ];

  programs = {
    lazydocker.enable = true;
    lazygit.enable = true;
    keepassxc.enable = true;
  };
}
