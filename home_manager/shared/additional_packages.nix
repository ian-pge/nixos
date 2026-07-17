{
  pkgs,
  config,
  inputs,
  ...
}: {
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

    # zed-editor
    mermaid-cli
    tmux
    rapidraw
    vscode
    pavucontrol
    devpod
    devcontainer
    orca-slicer
    (bambu-studio.override {
      withNvidiaGLWorkaround = true;
    })
    # bambuddy
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
    t3code
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
    nodejs_latest
    (symlinkJoin {
      name = "pi";
      paths = [inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi];
      nativeBuildInputs = [makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/pi \
          --set NPM_CONFIG_PREFIX ${config.home.homeDirectory}/.pi/agent/npm \
          --set NPM_CONFIG_CACHE ${config.home.homeDirectory}/.cache/pi/npm \
          --prefix PATH : ${lib.makeBinPath [nodejs_latest git]}
      '';
    })
    runpodctl
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
    chromium
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
