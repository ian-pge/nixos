{
  programs.hyprlock = {
    enable = true;

    # keep colour vars first
    importantPrefixes = ["$"];

    settings = {
      # ───────── Catppuccin Mocha palette ─────────
      "$rosewater" = "rgb(f4dbd6)";
      "$rosewaterAlpha" = "f4dbd6";
      "$flamingo" = "rgb(f0c6c6)";
      "$flamingoAlpha" = "f0c6c6";
      "$pink" = "rgb(f5bde6)";
      "$pinkAlpha" = "f5bde6";
      "$mauve" = "rgb(c6a0f6)";
      "$mauveAlpha" = "c6a0f6";
      "$red" = "rgb(ed8796)";
      "$redAlpha" = "ed8796";
      "$maroon" = "rgb(ee99a0)";
      "$maroonAlpha" = "ee99a0";
      "$peach" = "rgb(f5a97f)";
      "$peachAlpha" = "f5a97f";
      "$yellow" = "rgb(eed49f)";
      "$yellowAlpha" = "eed49f";
      "$green" = "rgb(a6da95)";
      "$greenAlpha" = "a6da95";
      "$teal" = "rgb(8bd5ca)";
      "$tealAlpha" = "8bd5ca";
      "$sky" = "rgb(91d7e3)";
      "$skyAlpha" = "91d7e3";
      "$sapphire" = "rgb(7dc4e4)";
      "$sapphireAlpha" = "7dc4e4";
      "$blue" = "rgb(8aadf4)";
      "$blueAlpha" = "8aadf4";
      "$lavender" = "rgb(b7bdf8)";
      "$lavenderAlpha" = "b7bdf8";
      "$text" = "rgb(cad3f5)";
      "$textAlpha" = "cad3f5";
      "$subtext1" = "rgb(b8c0e0)";
      "$subtext1Alpha" = "b8c0e0";
      "$subtext0" = "rgb(a5adcb)";
      "$subtext0Alpha" = "a5adcb";
      "$overlay2" = "rgb(939ab7)";
      "$overlay2Alpha" = "939ab7";
      "$overlay1" = "rgb(8087a2)";
      "$overlay1Alpha" = "8087a2";
      "$overlay0" = "rgb(6e738d)";
      "$overlay0Alpha" = "6e738d";
      "$surface2" = "rgb(5b6078)";
      "$surface2Alpha" = "5b6078";
      "$surface1" = "rgb(494d64)";
      "$surface1Alpha" = "494d64";
      "$surface0" = "rgb(363a4f)";
      "$surface0Alpha" = "363a4f";
      "$base" = "rgb(24273a)";
      "$baseAlpha" = "24273a";
      "$mantle" = "rgb(1e2030)";
      "$mantleAlpha" = "1e2030";
      "$crust" = "rgb(181926)";
      "$crustAlpha" = "181926";

      # ───────── General (no more `no_fade_in`) ─────────
      general = {
        grace = 300;
        hide_cursor = true;
      };

      # Turn *all* fade animations off (replacement for no_fade_in/out)
      animation = ["fade,0,0,default"]; # optional – drop if you like the fade

      # ───────── Backgrounds ─────────
      background = [
        {
          monitor = "eDP-1";
          path = "~/.config/hypr/wallpaper.jpg";
          blur_size = 2;
          blur_passes = 3;
          noise = 0.0117;
          contrast = 1.3;
          brightness = 0.8;
          vibrancy = 0.21;
          vibrancy_darkness = 0.0;
        }
        {
          monitor = "HDMI-A-1";
          path = "~/.config/hypr/wallpaper.jpg";
          blur_size = 2;
          blur_passes = 3;
          noise = 0.0117;
          contrast = 1.3;
          brightness = 0.8;
          vibrancy = 0.21;
          vibrancy_darkness = 0.0;
        }
      ];

      # ───────── Labels ─────────
      label = [
        # Time
        {
          monitor = "eDP-1";
          text = ''cmd[update:1000] echo "<b><big> $(date +\"%H:%M\") </big></b>"'';
          color = "rgba(33ccffee)";
          font_size = 112;
          font_family = "Geist Mono 10";
          shadow_passes = 3;
          shadow_size = 4;
          position = "0, -40";
          halign = "center";
          valign = "top";
        }

        # Day name
        {
          monitor = "eDP-1";
          text = ''cmd[update:1800000] echo "<b><big> $(date +'%A') </big></b>"'';
          color = "$text";
          font_size = 50;
          font_family = "UbuntuMono Nerd Font 10";
          position = "0, -220";
          halign = "center";
          valign = "top";
        }

        # Date
        {
          monitor = "eDP-1";
          text = ''cmd[update:1800000] echo "<b> $(date +'%d %b') </b>"'';
          color = "$text";
          font_size = 30;
          font_family = "UbuntuMono Nerd Font 10";
          position = "0, -280";
          halign = "center";
          valign = "top";
        }

        # Age ticker (single-line Python so it stays inside the string)
        {
          monitor = "eDP-1";
          text = ''            cmd[update:100] echo "<b><big>$(
                        python3 -c 'import datetime,sys;print(f\"{(datetime.datetime.now()-datetime.datetime(1998,11,15)).total_seconds()/31556952:.9f}\")'
                      )</big></b>"'';
          color = "$text";
          font_size = 20;
          font_family = "Geist Mono 10";
          position = "0, 40";
          halign = "center";
          valign = "bottom";
        }
      ];

      # ───────── Password box ─────────
      "input-field" = [
        {
          monitor = "eDP-1";
          size = "250, 50";
          outline_thickness = 3;
          dots_size = 0.26;
          dots_spacing = 0.64;
          dots_center = true;
          dots_rounding = -1; # ← typo fixed
          rounding = 22;
          outer_color = "$surface0";
          inner_color = "$surface0";
          font_color = "rgba(33ccffee)";
          fade_on_empty = true;
          placeholder_text = ''<span foreground="##$textAlpha"><i>󰌾 Logged in as </i><span foreground="##$mauveAlpha">$USER</span></span>'';
          position = "0, 0";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
