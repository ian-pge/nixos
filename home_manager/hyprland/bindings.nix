{
  helpers,
  hyprlockPackage,
  lib,
  pkgs,
  voxtypePackage,
}: let
  inherit
    (helpers)
    mainKey
    mkBind
    mkExec
    plainKey
    toLua
    ;

  workspaceCount = 8;

  # Cycle globally through the bar's numbered slots, including empty workspaces.
  # Absolute targets follow their assigned monitor instead of creating workspace 9.
  cycleWorkspace = step: ''
    function()
      local workspace = hl.get_active_workspace()
      if workspace == nil then
        return
      end

      local target
      if workspace.id < 1 or workspace.id > ${toString workspaceCount} then
        target = ${toString step} > 0 and 1 or ${toString workspaceCount}
      else
        target = ((workspace.id - 1 + (${toString step})) % ${toString workspaceCount}) + 1
      end
      hl.dispatch(hl.dsp.focus({ workspace = target }))
    end
  '';

  workspaceBinds = lib.concatMap (workspace: [
    (mkBind
      (mainKey (toString workspace))
      "hl.dsp.focus({ workspace = ${toString workspace} })"
      {})
    (mkBind
      (mainKey "SHIFT + ${toString workspace}")
      "hl.dsp.window.move({ workspace = ${toString workspace} })"
      {})
  ]) (lib.range 1 workspaceCount);

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

  startVoiceDictation = ''
    function()
      if quickshell_cycle_keyboard_cheatsheet(false) then
        return
      end
      hl.exec_cmd("${voxtypePackage}/bin/voxtype record start")
      hl.dispatch(hl.dsp.submap("voxtype"))
    end
  '';

  stopVoiceDictation = ''
    function()
      if hl.get_current_submap() ~= "voxtype" then
        return
      end

      hl.exec_cmd("${voxtypePackage}/bin/voxtype record stop")
      hl.dispatch(hl.dsp.submap("reset"))
    end
  '';

  stopVoiceDictationBinds = map (key:
    mkBind
    (plainKey key)
    stopVoiceDictation
    {
      release = true;
      ignore_mods = true;
      non_consuming = true;
      transparent = true;
    }) [
    "TAB"
    "SUPER + SUPER_L"
    "SUPER + SUPER_R"
  ];

  # Ordered compositor events avoid a late show process racing the release.
  hideKeyboardCheatsheetBinds = map (key:
    mkBind
    (plainKey key)
    ''function() quickshell_hide_keyboard_cheatsheet() end''
    {
      release = true;
      ignore_mods = true;
      non_consuming = true;
      transparent = true;
      submap_universal = true;
    }) ["apostrophe" "SUPER + SUPER_L" "SUPER + SUPER_R"];
in {
  terminal._var = "ghostty";
  browser._var = "google-chrome-stable";
  fileManager._var = "ghostty --class=dev.me.file --title=File -e /home/ian/.nix-profile/bin/yazi-open";
  fileManagerGraphic._var = "nautilus";
  calculator._var = "ghostty --class=dev.me.calc --title=Calculator -e kalker";
  menu._var = "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleLauncher";
  audio._var = "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleAudio";
  settings._var = "cosmic-settings";
  mainMod._var = "SUPER";

  bind =
    [
      (mkBind
        (plainKey "ESCAPE")
        ''          function()
                    if quickshell_dismiss_notification() then
                      return { ok = true }
                    end
                    return { ok = false, pass_event = true }
                  end''
        {auto_consuming = true;})
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
        (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar brightnessUp")
        {repeating = true;})
      (mkBind
        (plainKey "XF86MonBrightnessDown")
        (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar brightnessDown")
        {repeating = true;})

      (mkBind (plainKey "XF86AudioPlay") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar mediaPlayPause") {})
      (mkBind (plainKey "XF86AudioNext") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar mediaNext") {})
      (mkBind (plainKey "XF86AudioPrev") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar mediaPrevious") {})
      (mkBind (plainKey "XF86AudioMute") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleAudioMute") {})
      (mkBind (plainKey "XF86VoiceCommand") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleMicrophoneMute") {})
      (mkBind (plainKey "XF86DoNotDisturb") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleDoNotDisturb") {})
      # XKB names the physical F13 key XF86Tools with the default evdev rules.
      (mkBind (plainKey "XF86Tools") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleDoNotDisturb") {})
      (mkBind (plainKey "PRINT") (mkExec "hyprshot -m region -o ~/Pictures/Screenshots") {})
      (mkBind
        (plainKey "mouse:274")
        (mkExec "hyprshot -m region -o ~/Pictures/Screenshots")
        {release = true;})
      (mkBind (mainKey "RETURN") "hl.dsp.exec_cmd(terminal)" {})
      (mkBind (mainKey "W") "hl.dsp.window.close()" {})
      (mkBind (mainKey "CONTROL + Q") (mkExec "uwsm stop") {})
      (mkBind (mainKey "P") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleChromeTabs") {})
      (mkBind (mainKey "F") "hl.dsp.exec_cmd(fileManager)" {})
      (mkBind (mainKey "SHIFT + F") "hl.dsp.exec_cmd(fileManagerGraphic)" {})
      (mkBind (mainKey "N") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleWifi") {})
      (mkBind (mainKey "B") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleBluetooth") {})
      (mkBind (mainKey "U") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleUpdates") {})
      (mkBind (mainKey "Q") (mkExec "zeditor /home/ian/.config/nixos") {})
      (mkBind (mainKey "SHIFT + Q") "hl.dsp.exec_cmd(settings)" {})
      (mkBind (mainKey "R") "hl.dsp.exec_cmd(audio)" {})
      (mkBind (mainKey "A") "hl.dsp.exec_cmd(menu)" {})
      (mkBind (mainKey "apostrophe") "function() quickshell_show_keyboard_cheatsheet() end" {})
      (mkBind (mainKey "E") (mkExec "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleCalendar") {})
      (mkBind (mainKey "Z") ''hl.dsp.layout("togglesplit")'' {})
      (mkBind (mainKey "G") "hl.dsp.exec_cmd(browser)" {})
      (mkBind (mainKey "M") ''hl.dsp.workspace.toggle_special("Agenda")'' {})
      (mkBind (mainKey "X") "hl.dsp.exec_cmd(calculator)" {})

      (mkBind (mainKey "H") ''hl.dsp.focus({ direction = "left" })'' {})
      (mkBind (mainKey "L") ''hl.dsp.focus({ direction = "right" })'' {})
      (mkBind (mainKey "K") ''hl.dsp.focus({ direction = "up" })'' {})
      (mkBind (mainKey "J") ''hl.dsp.focus({ direction = "down" })'' {})
      (mkBind (mainKey "ALT + H") (cycleWorkspace (-1)) {})
      (mkBind (mainKey "ALT + L") (cycleWorkspace 1) {})
      (mkBind (mainKey "SHIFT + H") ''hl.dsp.window.move({ direction = "left" })'' {})
      (mkBind (mainKey "SHIFT + L") ''hl.dsp.window.move({ direction = "right" })'' {})
      (mkBind (mainKey "SHIFT + K") ''hl.dsp.window.move({ direction = "up" })'' {})
      (mkBind (mainKey "SHIFT + J") ''hl.dsp.window.move({ direction = "down" })'' {})
      (mkBind (mainKey "SPACE") ''hl.dsp.window.fullscreen({ mode = "maximized" })'' {})
      (mkBind (mainKey "SHIFT + SPACE") ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'' {})
      (mkBind
        (mainKey "TAB")
        startVoiceDictation
        {})
      (mkBind
        (mainKey "SHIFT + TAB")
        ''          function()
                    if quickshell_cycle_keyboard_cheatsheet(true) then
                      return { ok = true }
                    end
                    return { ok = false, pass_event = true }
                  end''
        {auto_consuming = true;})
      (mkBind (mainKey "CONTROL + h") ''hl.dsp.window.resize({ x = -50, y = 0, relative = true })'' {})
      (mkBind (mainKey "CONTROL + j") ''hl.dsp.window.resize({ x = 0, y = 50, relative = true })'' {})
      (mkBind (mainKey "CONTROL + k") ''hl.dsp.window.resize({ x = 0, y = -50, relative = true })'' {})
      (mkBind (mainKey "CONTROL + l") ''hl.dsp.window.resize({ x = 50, y = 0, relative = true })'' {})
    ]
    ++ workspaceBinds
    ++ specialWorkspaceBinds
    ++ [
      (mkBind
        (mainKey "ESCAPE")
        (mkExec "${pkgs.procps}/bin/pidof hyprlock || ${hyprlockPackage}/bin/hyprlock")
        {})
      (mkBind (mainKey "mouse:272") "hl.dsp.window.drag()" {mouse = true;})
      (mkBind (mainKey "mouse:273") "hl.dsp.window.resize()" {mouse = true;})
    ]
    ++ stopVoiceDictationBinds
    ++ hideKeyboardCheatsheetBinds;
}
