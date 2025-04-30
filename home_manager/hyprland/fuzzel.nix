{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        dpi-aware = "no";
        font = "Ubuntu Nerd Font:size=20";
        layer = "overlay";
        image-size-ratio = "1";
        horizontal-pad = "40";
        vertical-pad = "20";
        inner-pad = "15";
        line-height = "30";
      };
      colors = {
        background = "24273aff";
        text = "cad3f5ff";
        prompt = "a6da95ff";
        placeholder = "8087a2ff";
        input = "a6da95ff";
        match = "a6da95ff";
        selection = "5b6078ff";
        selection-text = "cad3f5ff";
        selection-match = "a6da95ff";
        counter = "8087a2ff";
        border = "33ff33ff";
      };
      border = {
        width = "3";
        radius = "20";
      };
    };
  };
}
