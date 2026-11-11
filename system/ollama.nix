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
    loadModels = ["qwen3.5:4b-q4_K_M"];
    environmentVariables.OLLAMA_NO_CLOUD = "1";
  };

  # Keep stable ownership for the state directory persisted by impermanence.
  systemd.services.ollama.serviceConfig = {
    DynamicUser = lib.mkForce false;
    # ReadWritePaths requires this directory before the service sandbox is set up.
    StateDirectory = ["ollama/models"];
    StateDirectoryMode = "0700";
  };
  environment.persistence."/persist/system".directories = [
    {
      directory = "/var/lib/ollama";
      user = "ollama";
      group = "ollama";
      mode = "0700";
    }
  ];
}
