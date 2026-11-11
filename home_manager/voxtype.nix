{pkgs, ...}: let
  # Keep the same pinned model file previously provided by the upstream module.
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
    hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
  };
in {
  services.voxtype = {
    enable = true;
    # Nixpkgs forces rusqlite to use system SQLite; the 1.1.1 recipe omits it.
    package = pkgs.voxtype-vulkan.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.sqlite];
    });

    settings = {
      engine = "whisper";
      state_file = "auto";

      # Preserve the defaults previously written by the upstream module.
      hotkey = {
        enabled = false;
        key = "SCROLLLOCK";
        modifiers = [];
      };

      audio = {
        pause_media = true;
        feedback.enabled = false;
      };

      # The desktop bar already renders the recording/transcription state.
      osd = {
        enabled = false;
        frontend = "gtk4";
        layout = "compact";
        style = "default";
      };

      status.icon_theme = "emoji";

      whisper = {
        model = "${whisperModel}";
        mode = "local";
        language = "fr";
        translate = false;
        gpu_isolation = true;
        flash_attention = true;
        context_window_optimization = false;
        on_demand_loading = false;
      };

      output = {
        mode = "type";
        type_delay_ms = 5;
        pre_type_delay_ms = 0;
        paste_keys = "shift+insert";
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
          on_no_speech = true;
        };
      };
    };
  };

  systemd.user.services.voxtype.Unit.After = ["pipewire.service" "pipewire-pulse.service"];
}
