# Preview-only refinements, merged into the installed Catppuccin theme so
# fenced code keeps the complete upstream syntax palette.
let
  macchiato = {
    text = "#cad3f5";
    subtext = "#b8c0e0";
    mantle = "#1e2030";
    surface = "#363a4f";
    mauve = "#c6a0f6";
    lavender = "#b7bdf8";
    blue = "#8aadf4";
    teal = "#8bd5ca";
    green = "#a6da95";
    yellow = "#eed49f";
    peach = "#f5a97f";
    pink = "#f5bde6";
  };
in {
  name = "Catppuccin Macchiato Markdown";
  appearance = "dark";
  style = {
    # Use Zed's native theme controls only. Headings and inline code share
    # the body text color; links, quotes and syntax have separate controls.
    text = macchiato.text;
    "text.muted" = macchiato.lavender;
    "text.accent" = macchiato.blue;
    "editor.foreground" = macchiato.peach;
    "editor.background" = macchiato.mantle;
    "border" = macchiato.mauve + "99";
    "border.variant" = macchiato.lavender + "80";
    "scrollbar.thumb.background" = macchiato.surface;
    "scrollbar.thumb.hover_background" = macchiato.mauve + "80";
    "scrollbar.track.background" = macchiato.mantle;
    "link_text.hover" = macchiato.teal;

    syntax = {
      comment = {color = macchiato.subtext;};
      keyword = {color = macchiato.mauve;};
      string = {color = macchiato.green;};
      number = {color = macchiato.peach;};
      function = {color = macchiato.blue;};
      type = {color = macchiato.yellow;};
      constant = {color = macchiato.peach;};
      operator = {color = macchiato.teal;};
      "punctuation.bracket" = {color = macchiato.lavender;};
      "punctuation.delimiter" = {color = macchiato.pink;};
      "string.escape" = {color = macchiato.pink;};
    };
  };
}
