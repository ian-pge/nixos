{pwaAppIds}: {
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
  workspace_rule = [
    {
      workspace = "special:Agenda";
      on_created_empty = "google-chrome-stable --profile-directory=Default --app-id=${pwaAppIds.calendar}";
    }
    {
      workspace = "special:Music";
      on_created_empty = "google-chrome-stable --profile-directory=Default --app-id=${pwaAppIds.spotify}";
    }
    {
      workspace = "special:Notes";
      on_created_empty = "google-chrome-stable --profile-directory=Default --app-id=${pwaAppIds.keep}";
    }
  ];
}
