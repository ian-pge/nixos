{
  helpers,
  lib,
  pkgs,
}: let
  inherit
    (helpers)
    mainKey
    mkBind
    mkExec
    plainKey
    toLua
    ;

  workspaceBinds = lib.concatMap (workspace: [
    (mkBind
      (mainKey (toString workspace))
      "hl.dsp.focus({ workspace = ${toString workspace} })"
      {})
    (mkBind
      (mainKey "SHIFT + ${toString workspace}")
      "hl.dsp.window.move({ workspace = ${toString workspace} })"
      {})
  ]) (lib.range 1 8);

  specialWorkspaceBinds =
    lib.concatMap (binding: [
      (mkBind
        (mainKey binding.key)
        "hl.dsp.workspace.toggle_special(${toLua binding.workspace})"
        {})
      (mkBind
        (mainKey "SHIFT + ${binding.key}")
        "hl.dsp.window.move({ workspace = ${toLua "special:${binding.workspace}"} })"
        {})
    ]) [
      {
        key = "S";
        workspace = "LLM";
      }
      {
        key = "D";
        workspace = "Chat";
      }
      {
        key = "C";
        workspace = "Music";
      }
      {
        key = "V";
        workspace = "Notes";
      }
    ];
in {
  terminal._var = "ghostty";
  browser._var = "google-chrome-stable";
  fileManager._var = "ghostty --class=dev.me.file --title=File -e /home/ian/.nix-profile/bin/yazi-open";
  fileManagerGraphic._var = "nautilus";
  calculator._var = "ghostty --class=dev.me.calc --title=Calculator -e kalker";
  menu._var = "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleLauncher";
  editor._var = "zeditor";
  audio._var = "pgrep -x pulsemixer >/dev/null 2>&1 || ghostty --class=dev.me.audio --title=Audio -e pulsemixer";
  settings._var = "cosmic-settings";
  mainMod._var = "SUPER";

  bind =
    [
      (mkBind
        (plainKey "XF86AudioRaiseVolume")
        (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar volumeUp")
        {repeating = true;})
      (mkBind
        (plainKey "XF86AudioLowerVolume")
        (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar volumeDown")
        {repeating = true;})
      (mkBind
        (plainKey "XF86MonBrightnessUp")
        (mkExec "${pkgs.brightnessctl}/bin/brightnessctl set +5%; ${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar showBrightness")
        {repeating = true;})
      (mkBind
        (plainKey "XF86MonBrightnessDown")
        (mkExec "${pkgs.brightnessctl}/bin/brightnessctl set 5%-; ${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar showBrightness")
        {repeating = true;})

      (mkBind (plainKey "XF86AudioPlay") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar mediaPlayPause") {})
      (mkBind (plainKey "XF86AudioNext") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar mediaNext") {})
      (mkBind (plainKey "XF86AudioPrev") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar mediaPrevious") {})
      (mkBind (plainKey "XF86AudioMute") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleAudioMute") {})
      (mkBind (plainKey "PRINT") (mkExec "hyprshot -m region -o ~/Pictures/Screenshots") {})
      (mkBind (mainKey "RETURN") "hl.dsp.exec_cmd(terminal)" {})
      (mkBind (mainKey "W") "hl.dsp.window.close()" {})
      (mkBind (mainKey "CONTROL + Q") (mkExec "uwsm stop") {})
      (mkBind (mainKey "P") (mkExec "ghostty --class=dev.me.pi --title=Pi -e pi") {})
      (mkBind (mainKey "F") "hl.dsp.exec_cmd(fileManager)" {})
      (mkBind (mainKey "SHIFT + F") "hl.dsp.exec_cmd(fileManagerGraphic)" {})
      (mkBind (mainKey "N") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleWifi") {})
      (mkBind (mainKey "B") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleBluetooth") {})
      (mkBind (mainKey "U") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleUpdates") {})
      (mkBind (mainKey "Q") (mkExec "zeditor /home/ian/.config/nixos") {})
      (mkBind (mainKey "SHIFT + Q") "hl.dsp.exec_cmd(settings)" {})
      (mkBind (mainKey "R") "hl.dsp.exec_cmd(audio)" {})
      (mkBind (mainKey "A") "hl.dsp.exec_cmd(menu)" {})
      (mkBind (mainKey "code:47") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleChromeTabs") {})
      (mkBind (mainKey "E") "hl.dsp.exec_cmd(editor)" {})
      (mkBind (mainKey "Z") ''hl.dsp.layout("togglesplit")'' {})
      (mkBind (mainKey "G") "hl.dsp.exec_cmd(browser)" {})
      (mkBind (mainKey "M") ''hl.dsp.workspace.toggle_special("Agenda")'' {})
      (mkBind (mainKey "X") "hl.dsp.exec_cmd(calculator)" {})

      (mkBind (mainKey "H") ''hl.dsp.focus({ direction = "left" })'' {})
      (mkBind (mainKey "L") ''hl.dsp.focus({ direction = "right" })'' {})
      (mkBind (mainKey "K") ''hl.dsp.focus({ direction = "up" })'' {})
      (mkBind (mainKey "J") ''hl.dsp.focus({ direction = "down" })'' {})
      (mkBind (mainKey "SHIFT + H") ''hl.dsp.window.move({ direction = "left" })'' {})
      (mkBind (mainKey "SHIFT + L") ''hl.dsp.window.move({ direction = "right" })'' {})
      (mkBind (mainKey "SHIFT + K") ''hl.dsp.window.move({ direction = "up" })'' {})
      (mkBind (mainKey "SHIFT + J") ''hl.dsp.window.move({ direction = "down" })'' {})
      (mkBind (mainKey "SPACE") ''hl.dsp.window.fullscreen({ mode = "maximized" })'' {})
      (mkBind (mainKey "SHIFT + SPACE") ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'' {})
      (mkBind (mainKey "CONTROL + h") ''hl.dsp.window.resize({ x = -50, y = 0, relative = true })'' {})
      (mkBind (mainKey "CONTROL + j") ''hl.dsp.window.resize({ x = 0, y = 50, relative = true })'' {})
      (mkBind (mainKey "CONTROL + k") ''hl.dsp.window.resize({ x = 0, y = -50, relative = true })'' {})
      (mkBind (mainKey "CONTROL + l") ''hl.dsp.window.resize({ x = 50, y = 0, relative = true })'' {})
    ]
    ++ workspaceBinds
    ++ specialWorkspaceBinds
    ++ [
      (mkBind (mainKey "ESCAPE") (mkExec "hyprlock") {})
      (mkBind (mainKey "mouse:272") "hl.dsp.window.drag()" {mouse = true;})
      (mkBind (mainKey "mouse:273") "hl.dsp.window.resize()" {mouse = true;})
    ];
}
