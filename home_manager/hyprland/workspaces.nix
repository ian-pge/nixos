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

  workspace_rule = [
    {
      workspace = "5";
      monitor = "eDP-1";
      persistent = true;
    }
    {
      workspace = "6";
      monitor = "eDP-1";
      persistent = true;
    }
    {
      workspace = "7";
      monitor = "eDP-1";
      persistent = true;
    }
    {
      workspace = "8";
      monitor = "eDP-1";
      persistent = true;
    }
    {
      workspace = "1";
      monitor = "DP-2";
      persistent = true;
    }
    {
      workspace = "2";
      monitor = "DP-2";
      persistent = true;
    }
    {
      workspace = "3";
      monitor = "DP-2";
      persistent = true;
    }
    {
      workspace = "4";
      monitor = "DP-2";
      persistent = true;
    }
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
