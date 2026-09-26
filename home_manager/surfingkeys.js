// Managed by Home Manager. Edit this file in the NixOS repository.
// Surfingkeys supplies `settings` and `api` to configuration scripts.
settings.smoothScroll = false;
settings.hintAlign = "left";

// J: next tab; K: previous tab (replaces the default tab-moving shortcuts).
api.map("J", "R");
api.map("K", "E");

// Catppuccin Macchiato, with the Sapphire accent used elsewhere in this config.
// Palette: https://github.com/catppuccin/palette
settings.theme = `
  .sk_theme, #sk_omnibar, #sk_usage, #sk_popup, #sk_status,
  #sk_find, #sk_keystroke, #sk_banner, #sk_bubble {
    background: #24273a;
    color: #cad3f5;
    border-color: #494d64;
    color-scheme: dark;
  }
  .sk_theme input {
    background: transparent;
    color: #cad3f5;
    caret-color: #7dc4e4;
  }
  .sk_theme input::placeholder {
    color: #a5adcb;
  }
  .sk_theme .url, #sk_tabs .sk_tab_url {
    color: #8aadf4;
  }
  .sk_theme .annotation, .expandRichHints span.annotation {
    color: #b8c0e0;
  }
  .sk_theme .omnibar_highlight, .sk_theme .feature_name,
  .sk_theme .prompt {
    color: #7dc4e4;
  }
  .sk_theme .omnibar_folder {
    color: #c6a0f6;
  }
  .sk_theme .omnibar_timestamp, .sk_theme .omnibar_visitcount,
  .sk_theme .resultPage {
    color: #a5adcb;
  }
  .sk_theme .separator {
    color: #eed49f;
  }
  #sk_omnibarSearchArea, #sk_usage .feature_name > span {
    border-color: #494d64;
  }
  .sk_theme #sk_omnibarSearchResult > ul > li:nth-child(odd) {
    background: #1e2030;
  }
  .sk_theme #sk_omnibarSearchResult > ul > li.focused {
    background: #363a4f;
    box-shadow: inset 3px 0 #7dc4e4;
  }
  .sk_theme #sk_omnibarSearchResult > ul > li.window {
    border-color: #494d64;
  }
  .sk_theme #sk_omnibarSearchResult > ul > li.window.focused {
    border-color: #7dc4e4;
  }
  .sk_theme kbd, #sk_keystroke kbd {
    background: #363a4f;
    color: #7dc4e4;
    border-color: #494d64;
    box-shadow: none;
  }
  .expandRichHints kbd > .candidates {
    color: #f5a97f;
  }
  #sk_tabs {
    background: #181926;
  }
  #sk_tabs .sk_tab, #sk_tabs .sk_tab_group {
    background: #24273a;
    color: #cad3f5;
    border-color: #494d64;
    box-shadow: none;
  }
  #sk_tabs .sk_tab_title {
    color: #cad3f5;
  }
  #sk_tabs .sk_tab_hint {
    background: #7dc4e4;
    color: #181926;
    border-color: #7dc4e4;
    box-shadow: none;
  }
  #sk_bubble * {
    color: #cad3f5 !important;
  }
  div.sk_arrow[dir=down] > div:nth-of-type(1) { border-top-color: #494d64; }
  div.sk_arrow[dir=up] > div:nth-of-type(1) { border-bottom-color: #494d64; }
  div.sk_arrow[dir=down] > div:nth-of-type(2) { border-top-color: #24273a; }
  div.sk_arrow[dir=up] > div:nth-of-type(2) { border-bottom-color: #24273a; }

  /* Built-in Ace editor (Vim input): Surfingkeys sets its background inline. */
  #sk_editor.ace_editor {
    background: #24273a !important;
    color: #cad3f5;
    color-scheme: dark;
    border: 1px solid #494d64;
  }
  #sk_editor .ace_gutter {
    background: #1e2030;
    color: #a5adcb;
  }
  #sk_editor .ace_gutter-active-line,
  #sk_editor .ace_marker-layer .ace_active-line {
    background: #363a4f;
  }
  #sk_editor .ace_marker-layer .ace_selection {
    background: #494d64;
  }
  #sk_editor.ace_multiselect .ace_selection.ace_start {
    box-shadow: 0 0 3px #24273a;
  }
  #sk_editor .ace_marker-layer .ace_selected-word {
    background: #363a4f;
    border-color: #7dc4e4;
  }
  #sk_editor .ace_marker-layer .ace_bracket {
    border-color: #7dc4e4;
  }
  /* Bright yellow matches Theme.state in desktop/ui/Theme.js. */
  #sk_editor .ace_cursor {
    color: #ffcc33;
  }
  #sk_editor.normal-mode .ace_cursor {
    background: #ffcc33;
    border: none;
  }
  #sk_editor.normal-mode .ace_hidden-cursors .ace_cursor {
    background: transparent;
    border: 1px solid #ffcc33;
  }
  #sk_editor .ace_print-margin {
    background: #363a4f;
  }
  #sk_editor .ace_invisible {
    color: #6e738d;
  }
  #sk_editor .ace_indent-guide {
    background: linear-gradient(to bottom, #494d64 50%, transparent 50%) right / 1px 4px repeat-y;
  }
  #sk_editor .ace_comment { color: #939ab7; font-style: italic; }
  #sk_editor .ace_keyword, #sk_editor .ace_storage { color: #c6a0f6; }
  #sk_editor .ace_keyword.ace_operator { color: #91d7e3; }
  #sk_editor .ace_string { color: #a6da95; }
  #sk_editor .ace_string.ace_regexp { color: #f5bde6; }
  #sk_editor .ace_constant, #sk_editor .ace_constant.ace_numeric,
  #sk_editor .ace_constant.ace_language, #sk_editor .ace_constant.ace_library,
  #sk_editor .ace_constant.ace_buildin { color: #f5a97f; }
  #sk_editor .ace_variable { color: #cad3f5; }
  #sk_editor .ace_variable.ace_parameter { color: #f4dbd6; }
  #sk_editor .ace_entity.ace_name.ace_function,
  #sk_editor .ace_support.ace_function { color: #8aadf4; }
  #sk_editor .ace_entity.ace_name.ace_tag,
  #sk_editor .ace_meta.ace_tag { color: #8aadf4; }
  #sk_editor .ace_entity.ace_other.ace_attribute-name { color: #eed49f; }
  #sk_editor .ace_support.ace_type, #sk_editor .ace_support.ace_class,
  #sk_editor .ace_support.ace_constant { color: #eed49f; }
  #sk_editor .ace_invalid { background: #ed8796; color: #181926; }
  #sk_editor .ace_fold { background: #7dc4e4; border-color: #cad3f5; }

  /* Vim's : command line, / search and unsaved-changes prompt. */
  #sk_editor .ace_dialog {
    background: #1e2030;
    color: #cad3f5;
    border-color: #494d64;
  }
  #sk_editor .ace_dialog input {
    background: transparent;
    color: #cad3f5;
    caret-color: #ffcc33;
  }
  #sk_editor .ace_dialog input::selection {
    background: #494d64;
    color: #cad3f5;
  }
  /* Ace appends its completion menu to the body, outside #sk_editor. */
  body .ace_editor.ace_autocomplete {
    background: #1e2030;
    color: #cad3f5;
    border-color: #494d64;
  }
  body .ace_editor.ace_autocomplete .ace_marker-layer .ace_active-line,
  body .ace_editor.ace_autocomplete .ace_line-hover {
    background: #363a4f;
    border-color: #7dc4e4;
  }
  body .ace_editor.ace_autocomplete .ace_completion-highlight {
    color: #7dc4e4;
  }
`;

// Link hints live outside the Surfingkeys UI iframe and need their own styles.
api.Hints.style(`
  background: #7dc4e4;
  color: #181926;
  border: 1px solid #24273a;
  border-radius: 4px;
  box-shadow: none;
  font-weight: bold;
`);
api.Hints.style(`
  div {
    background: #eed49f;
    color: #181926;
    border: 1px solid #24273a;
    border-radius: 4px;
  }
  div.begin { color: #ed8796; }
`, "text");
api.Visual.style("marks", "background-color: #eed49f; color: #181926;");
api.Visual.style("cursor", "background-color: #7dc4e4; color: #181926;");
