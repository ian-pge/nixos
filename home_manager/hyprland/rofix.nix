{pkgs, ...}: {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    theme = ''
      /*****--------------------------------------------------------------*****
       *   Combined theme  –  style-7 (type-4)                               *
       *   Author : Aditya Shakya (adi1090x)                                 *
       *****-----------------------------------------------------------------**/

      /*-----------------  Colours & Fonts (in-lined)  ----------------------*/
      * {
        /* Catppuccin palette */
        background:         transparent;
        background-alt:     rgba(40,40,57,0.90);
        foreground:         #D9E0EEFF;
        selected:           #7AA2F7FF;
        active:             #ABE9B3FF;
        urgent:             #F28FADFF;

        /* Font */
        font: "Ubuntu sans-serif 20";
      }

      /*-----------------  Configuration overrides for the theme  -----------*/
      configuration {
        modi:                       "drun";
        show-icons:                 true;
        display-drun:               "drun :";
        display-run:                "";
        display-filebrowser:        "";
        display-window:             "";
        drun-display-format:        "{name} [<span weight='light' size='small'><i>({generic})</i></span>]";
        window-format:              "{w} · {c} · {t}";
      }

      /*-----------------  Global properties  ------------------------------*/
      * {
        border-colour:               var(selected);
        handle-colour:               var(selected);
        background-colour:           var(background);
        foreground-colour:           var(foreground);
        alternate-background:        var(background-alt);

        normal-background:           var(background);
        normal-foreground:           var(foreground);

        urgent-background:           var(urgent);
        urgent-foreground:           var(background);

        active-background:           var(active);
        active-foreground:           var(background);

        selected-normal-background:  var(selected);
        selected-normal-foreground:  var(background);

        selected-urgent-background:  var(active);
        selected-urgent-foreground:  var(background);

        selected-active-background:  var(urgent);
        selected-active-foreground:  var(background);

        alternate-normal-background: var(background);
        alternate-normal-foreground: var(foreground);

        alternate-urgent-background: var(urgent);
        alternate-urgent-foreground: var(background);

        alternate-active-background: var(active);
        alternate-active-foreground: var(background);
      }

      /*-----------------  Window  -----------------------------------------*/
      window {
        transparency:       "real";
        location:           center;
        anchor:             center;
        fullscreen:         true;
        width:              1366px;
        height:             768px;

        margin:             0px;
        padding:            0px;
        border:             0px;
        background-color:   @background-colour;
      }

      /*-----------------  Main box  ---------------------------------------*/
      mainbox {
        spacing:            20px;
        padding:            25% 35%;
        background-color:   transparent;
        children:           [ "inputbar", "listview" ];
      }

      /*-----------------  Input bar  --------------------------------------*/
      inputbar {
        spacing:            10px;
        padding:            20px;
        border-radius:      20px;
        background-color:   @alternate-background;
        text-color:         #33ccffee;
        children:           [ "entry" ];
      }
      prompt, textbox-prompt-colon, entry {
        background-color:   transparent;
        text-color:         inherit;
      }
      entry {
        cursor:             text;
        placeholder:        "Type here to search for apps";
        horizontal-align:   0.5;
      }

      /*-----------------  List view  --------------------------------------*/
      listview {
        columns:            1;
        lines:              12;
        cycle:              true;
        scrollbar:          false;

        spacing:            10px;
        padding:            30px;
        border-radius:      20px;
        background-color:   @alternate-background;
      }
      scrollbar {
        handle-width:       5px;
        handle-color:       @handle-colour;
        background-color:   @alternate-background;
      }

      /*-----------------  Elements (rows)  --------------------------------*/
      element {
        padding:            8px;
        border-radius:      12px;
      }
      element selected.normal {
        background-color:   white / 10%;
      }

      /*-----------------  Mode switcher buttons  --------------------------*/
      mode-switcher {
        spacing:            10px;
      }
      button {
        padding:            10px;
        background-color:   @alternate-background;
      }
      button selected {
        background-color:   var(selected-normal-background);
        text-color:         var(selected-normal-foreground);
      }

      /*-----------------  Messages  ---------------------------------------*/
      message, textbox {
        background-color:   transparent;
      }
    '';
  };
}
