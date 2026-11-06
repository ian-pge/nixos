{
  monitor = [
    {
      output = "DP-2";
      mode = "5120x2160@120";
      position = "0x0";
      scale = 1.25;
    }
    {
      output = "eDP-1";
      mode = "2560x1600@165";
      position = "4096x728";
      scale = 1.6;
    }
  ];

  # Numbered workspace rules are maintained by workspace-policy.lua at runtime.
  # Special workspaces launch their PWA from the workspace.created handler in
  # default.nix.
}
