{
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    package-version-server
    nil
    nixd
    nixpkgs-fmt
    alejandra
    texlive.combined.scheme-full
    texlab
    texpresso

    # zed-editor
    mermaid-cli
    tmux
    rapidraw
    vscode
    pavucontrol
    devbox
    devpod
    devcontainer
    t3code
    orca-slicer
    # (bambu-studio.override {
    # withNvidiaGLWorkaround = true;
    # })
    herdr
    kalker
    google-chrome
    blender
    davinci-resolve
    nvd
    nix-output-monitor
    zotero
    fastfetch
    obsidian
    # freecad-wayland
    firefox
    # gyroflow
    wget
    pika-backup
    inkscape
    polychromatic
    razergenie
    unrar
    mutagen
    antigravity
    ffmpeg-full
    # f3d # disabled: pulls vtk -> pdal -> gdal-minimal, currently failing GDAL tests
    discord
    krabby
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
    (symlinkJoin {
      name = "pi";
      paths = [inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi];
      nativeBuildInputs = [makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/pi \
          --prefix PATH : ${lib.makeBinPath [nodejs_latest]}
      '';
    })
    runpodctl
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
    chezmoi
    ookla-speedtest
  ];

  programs = {
    lazydocker.enable = true;
    lazygit.enable = true;
    keepassxc.enable = true;
    obs-studio.enable = true;
  };
}
