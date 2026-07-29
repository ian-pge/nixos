{
  inputs,
  pkgs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  llmAgents = inputs.llm-agents.packages.${system};

  t3codeIcon = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/pingdotgg/t3code/v0.0.30/assets/prod/logo.svg";
    hash = "sha256-+87dvO63UTb7jixwLPD+RZ0VO2Kau9piYqY9fExl5nM=";
  };

  t3codeUpdate = pkgs.writeShellApplication {
    name = "t3code-update";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      util-linux
    ];
    text = ''
      install_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/t3code"
      appimage="$install_dir/T3-Code.AppImage"
      version_file="$install_dir/version"
      release_url="https://api.github.com/repos/pingdotgg/t3code/releases/latest"

      mkdir -p "$install_dir"

      # Do not queue multiple large downloads when the timer or a manual update
      # is already running.
      exec 9>"$install_dir/update.lock"
      if ! flock --nonblock 9; then
        echo "Another T3 Code update is already in progress."
        exit 0
      fi

      release_json="$(mktemp)"
      downloaded_app=""
      downloaded_version=""
      previous_app=""
      cleanup() {
        rm -f "$release_json"
        if [[ -n "$downloaded_app" ]]; then
          rm -f "$downloaded_app"
        fi
        if [[ -n "$downloaded_version" ]]; then
          rm -f "$downloaded_version"
        fi
        if [[ -n "$previous_app" ]]; then
          rm -f "$previous_app"
        fi
      }
      trap cleanup EXIT

      curl \
        --fail \
        --location \
        --retry 3 \
        --connect-timeout 10 \
        --max-time 30 \
        --show-error \
        --silent \
        --header "Accept: application/vnd.github+json" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        "$release_url" \
        --output "$release_json"

      release="$(jq -c '
        select(.draft == false and .prerelease == false)
      ' "$release_json")"

      if [[ -z "$release" ]]; then
        echo "No stable T3 Code release was found." >&2
        exit 1
      fi

      tag="$(jq -r '.tag_name' <<<"$release")"
      asset="$(jq -c '
        [.assets[] | select(.name | endswith("-x86_64.AppImage"))][0] // empty
      ' <<<"$release")"

      if [[ -z "$asset" ]]; then
        echo "The $tag release has no x86_64 AppImage." >&2
        exit 1
      fi

      if [[ -x "$appimage" && -f "$version_file" && "$(<"$version_file")" == "$tag" ]]; then
        echo "T3 Code is already up to date ($tag)."
        exit 0
      fi

      download_url="$(jq -r '.browser_download_url' <<<"$asset")"
      digest="$(jq -r '.digest // empty' <<<"$asset")"
      expected_sha256="''${digest#sha256:}"

      if [[ "$digest" != sha256:* || ! "$expected_sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "GitHub did not provide a valid SHA-256 digest for $tag." >&2
        exit 1
      fi

      downloaded_app="$(mktemp "$install_dir/.T3-Code.AppImage.XXXXXX")"
      echo "Downloading T3 Code $tag..."
      curl \
        --fail \
        --location \
        --retry 3 \
        --connect-timeout 15 \
        --max-time 1800 \
        --speed-limit 1024 \
        --speed-time 30 \
        --show-error \
        --progress-bar \
        "$download_url" \
        --output "$downloaded_app"

      actual_sha256="$(sha256sum "$downloaded_app" | cut -d ' ' -f 1)"
      if [[ "''${actual_sha256,,}" != "''${expected_sha256,,}" ]]; then
        echo "SHA-256 verification failed for $tag." >&2
        exit 1
      fi

      chmod 0755 "$downloaded_app"

      # Keep one verified previous version available for manual recovery from a
      # broken release. Btrfs can make this copy as a cheap reflink.
      if [[ -x "$appimage" ]]; then
        previous_app="$(mktemp "$install_dir/.T3-Code.previous.AppImage.XXXXXX")"
        cp --reflink=auto --preserve=mode "$appimage" "$previous_app"
        mv -f "$previous_app" "$install_dir/T3-Code.previous.AppImage"
        previous_app=""
        if [[ -f "$version_file" ]]; then
          cp -f "$version_file" "$install_dir/previous-version"
        fi
      fi

      mv -f "$downloaded_app" "$appimage"
      downloaded_app=""

      downloaded_version="$(mktemp "$install_dir/.version.XXXXXX")"
      printf '%s\n' "$tag" >"$downloaded_version"
      mv -f "$downloaded_version" "$version_file"
      downloaded_version=""

      echo "Installed T3 Code $tag."
    '';
  };

  t3codeLauncher = pkgs.writeShellApplication {
    name = "t3code";
    runtimeInputs = [
      t3codeUpdate
      pkgs.git
      pkgs.gh
      llmAgents.codex
      llmAgents.claude-code
      llmAgents.gemini-cli
      llmAgents.opencode
    ];
    text = ''
      install_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/t3code"
      appimage="$install_dir/T3-Code.AppImage"

      # The locked timer/update command is the single update authority. Letting
      # Electron replace the AppImage independently would race it and bypass the
      # verified backup rotation.
      export T3CODE_DISABLE_AUTO_UPDATE=1

      if [[ "''${1:-}" == "--previous" ]]; then
        previous="$install_dir/T3-Code.previous.AppImage"
        if [[ ! -x "$previous" ]]; then
          echo "No previous T3 Code release is available." >&2
          exit 1
        fi
        shift
        exec "$previous" "$@"
      fi

      # Only the initial installation is synchronous. Once installed, launch
      # immediately and leave routine network checks to the update timer.
      if [[ ! -x "$appimage" ]]; then
        t3code-update || true
        if [[ ! -x "$appimage" ]]; then
          echo "T3 Code is not installed. The download failed or another update is still in progress; retry shortly." >&2
          exit 1
        fi
      fi

      exec "$appimage" "$@"
    '';
  };
in {
  home.packages = [
    t3codeLauncher
    t3codeUpdate
  ];

  xdg.dataFile."icons/hicolor/scalable/apps/t3code.svg".source = t3codeIcon;

  xdg.dataFile."applications/t3code.desktop" = {
    # Electron replaces this entry with a regular file when registering the
    # t3code: URL handler. Reassert the managed entry on the next activation
    # instead of repeatedly creating colliding .backup files.
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=T3 Code
      GenericName=AI coding environment
      Comment=Minimal web GUI for coding agents
      Exec=${t3codeLauncher}/bin/t3code %U
      Icon=t3code
      Terminal=false
      Categories=Development;
      StartupWMClass=t3code
      MimeType=x-scheme-handler/t3code;
    '';
  };

  systemd.user.services.t3code-update = {
    Unit = {
      Description = "Update the stable T3 Code AppImage";
      After = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${t3codeUpdate}/bin/t3code-update";
    };
  };

  systemd.user.timers.t3code-update = {
    Unit.Description = "Periodically update stable T3 Code";
    Timer = {
      OnBootSec = "5m";
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
