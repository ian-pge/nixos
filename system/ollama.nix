{
  lib,
  pkgs,
  ...
}: {
  # CUDA-enabled packages are published separately from cache.nixos.org.
  nix.settings = {
    extra-substituters = ["https://cache.nixos-cuda.org"];
    extra-trusted-public-keys = ["cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="];
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    user = "ollama";
    host = "127.0.0.1";
    loadModels = ["huihui_ai/qwen3.5-abliterated:9b"];
    environmentVariables = {
      OLLAMA_NO_CLOUD = "1";
      # pi's agent prompt and tool results need more than the default window.
      OLLAMA_CONTEXT_LENGTH = "32768";
    };
  };

  systemd.services.ollama = {
    requires = ["ollama-nvidia-init.service"];
    after = ["ollama-nvidia-init.service"];
    serviceConfig = {
      # Keep stable ownership for the state directory persisted by impermanence.
      DynamicUser = lib.mkForce false;
      # ReadWritePaths requires this directory before the service sandbox is set up.
      StateDirectory = ["ollama/models"];
      StateDirectoryMode = "0700";
    };
  };

  # Initialize CUDA devices before systemd resolves Ollama's char-nvidia-* allow
  # list. ExecStartPre in Ollama itself would run after that sandbox is created.
  systemd.services.ollama-nvidia-init = {
    description = "Prepare NVIDIA devices for Ollama";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [
        "${pkgs.nvidia-modprobe}/bin/nvidia-modprobe -c 0 -c 255"
        "${pkgs.nvidia-modprobe}/bin/nvidia-modprobe -u -c 0"
      ];
    };
  };
}
