{
  programs.hyprlock = {
    enable = true;

    settings = {
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

      general = {hide_cursor = true;};

      animations = {
        bezier = "ease,0.42,0,1,1";
        animation = "fadeIn, 1, 10, ease";
      };

      background = [
        {
          monitor = "eDP-1";
          path = "screenshot";
          blur_size = 2;
          blur_passes = 3;
          noise = 0.0117;
          contrast = 1.3;
          brightness = 0.4;
          vibrancy = 0.21;
          vibrancy_darkness = 0.0;
        }
        {monitor = "HDMI-A-1";}
      ];

      label = [
        {
          monitor = "eDP-1";
          text = ''cmd[update:1000] echo "<b><big> $(date +'%H:%M') </big></b>"'';
          color = "$sapphire";
          font_size = 112;
          font_family = "Ubuntu Nerd Font";
          shadow_passes = 3;
          shadow_size = 4;
          position = "0, -40";
          halign = "center";
          valign = "top";
        }
        # …Duplicate for each label block
      ];

      "input-field" = {
        # hypr syntax allows hyphens in section names
        monitor = "eDP-1";
        size = "250, 50";
        outline_thickness = 3;
        dots_size = 0.26;
        dots_spacing = 0.64;
        dots_center = true;
        rounding = 22;
        outer_color = "$crust";
        inner_color = "$crust";
        font_color = "$green";
        fade_on_empty = true;
        placeholder_text = ''<span foreground="##${"$textAlpha"}"><i>󰌾 Logged in as </i><span foreground="##${"$mauveAlpha"}">$USER</span></span>'';
        position = "0, 0";
        halign = "center";
        valign = "center";
      };
    };
  };
}
