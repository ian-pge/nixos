{pkgs, ...}: {
  home.packages = with pkgs; [
    clang-tools
    package-version-server
    nil
    nixd
    nixpkgs-fmt
    alejandra
    texlive.combined.scheme-full
    texlab
    texpresso

    zathura
    # zed-editor
    vscode
    pavucontrol
    devpod
    bambu-studio
    kalker
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
    obs-studio.enable = true;
  };
}
