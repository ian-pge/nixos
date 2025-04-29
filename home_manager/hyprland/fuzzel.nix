{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        dpi-aware = "no";
        font = "Ubuntu Nerd Font:size=20";
        layer = "overlay";
        icon-theme = "Adwaita";
        image-size-ratio = "1";
      };
      colors = {
        background = "24273aff";
        text = "cad3f5ff";
        prompt = "b8c0e0ff";
        placeholder = "8087a2ff";
        input = "cad3f5ff";
        match = "8aadf4ff";
        selection = "5b6078ff";
        selection-text = "cad3f5ff";
        selection-match = "eed49fff";
        counter = "8087a2ff";
        border = "ff3333ff";
      };
      border = {
        width = "3";
        radius = "10";
      };
    };
  };
}
