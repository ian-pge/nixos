{
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    package-version-server
    nil
    nixpkgs-fmt
    alejandra
    texliveFull
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
    ((bambu-studio.override {
        withNvidiaGLWorkaround = true;
      }).overrideAttrs (old: {
        env =
          (old.env or {})
          // {
            NIX_BUILD_CORES = "12";
          };
      }))
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
    antigravity-ide
    ffmpeg-full
    # f3d # disabled: pulls vtk -> pdal -> gdal-minimal, currently failing GDAL tests
    discord
    krabby
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
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
