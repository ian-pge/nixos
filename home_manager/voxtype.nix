{
  config,
  inputs,
  pkgs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
in {
  imports = [inputs.voxtype.homeManagerModules.default];

  programs.voxtype = {
    enable = true;
    engine = "whisper";
    package = inputs.voxtype.packages.${system}.vulkan;
    model.name = "large-v3-turbo";
    service.enable = true;

    settings = {
      state_file = "auto";

      hotkey.enabled = false;

      audio = {
        pause_media = true;
        feedback.enabled = false;
      };

      # The desktop bar already renders the recording/transcription state.
      osd.enabled = false;

      whisper = {
        mode = "local";
        language = "fr";
        translate = false;
        gpu_isolation = true;
        flash_attention = true;
        context_window_optimization = false;
      };

      output = {
        mode = "type";
        driver_order = [
          "wtype"
          "clipboard"
        ];
        append_text = " ";
        shift_enter_newlines = true;

        notification = {
          on_recording_start = false;
          on_recording_stop = false;
          on_transcription = false;
        };
      };
    };
  };

  systemd.user.services.voxtype.Unit.X-Restart-Triggers = [
    "${config.xdg.configFile."voxtype/config.toml".source}"
  ];
}
