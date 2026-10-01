{
  lib,
  runCommand,
  writeShellApplication,
  ghostty,
  yazi,
  jq,
  pipewire,
  sound-theme-freedesktop,
  quickshellSystemStats,
  quickshellWeather,
  quickshellBeeper,
  claude-code,
  codex,
  coreutils,
  systemd,
}: let
  attachmentPicker = writeShellApplication {
    name = "quickshell-beeper-pick-file";
    runtimeInputs = [coreutils ghostty yazi jq];
    text = builtins.readFile ../../tools/quickshell/pick-attachment.sh;
  };
  source = lib.cleanSourceWith {
    src = ../../desktop;
    filter = path: type: let
      name = baseNameOf path;
    in
      if type == "directory"
      then !(builtins.elem name ["tests" "docs" "previews"])
      else if builtins.elem name ["glass-test.qml" "pill-test.qml" "selection-test.qml"]
      then false
      else
        name
        == "qmldir"
        || lib.any (extension: lib.hasSuffix extension name) [
          ".qml"
          ".js"
          ".svg"
          ".png"
          ".jpg"
          ".webp"
          ".gif"
          ".ttf"
          ".otf"
          ".qsb"
        ];
  };
in
  runCommand "quickshell-desktop" {} ''
    cp -R ${source} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/features/system/SystemController.qml" \
      --replace-fail '"quickshell-system-stats"' '"${quickshellSystemStats}/bin/quickshell-system-stats"'
    substituteInPlace "$out/features/storage/StorageController.qml" \
      --replace-fail '["systemctl",' '["${systemd}/bin/systemctl",' \
      --replace-fail '["cat",' '["${coreutils}/bin/cat",'
    substituteInPlace "$out/features/calendar/WeatherData.qml" \
      --replace-fail '"quickshell-weather"' '"${quickshellWeather}/bin/quickshell-weather"'
    substituteInPlace "$out/features/messenger/BeeperData.qml" \
      --replace-fail '"quickshell-beeper"' '"${quickshellBeeper}/bin/quickshell-beeper"'
    substituteInPlace "$out/features/messenger/BeeperAttachmentPicker.qml" \
      --replace-fail 'property var command: ["bash", Qt.resolvedUrl("../../../tools/quickshell/pick-attachment.sh").toString().replace(/^file:\/\//, "")]' \
        'property var command: ["${attachmentPicker}/bin/quickshell-beeper-pick-file"]'
    # The same CLI builds as the user's profile, so they share its sign-in state.
    substituteInPlace "$out/features/usage/UsageController.qml" \
      --replace-fail 'claudeCommand: ["claude",' 'claudeCommand: ["${claude-code}/bin/claude",' \
      --replace-fail 'codexCommand: ["codex",' 'codexCommand: ["${codex}/bin/codex",'
    substituteInPlace "$out/features/audio/AudioAvailability.qml" \
      --replace-fail '"pw-dump"' '"${pipewire}/bin/pw-dump"'
    substituteInPlace "$out/features/notifications/NotificationData.qml" \
      --replace-fail '"pw-play"' '"${pipewire}/bin/pw-play"' \
      --replace-fail '"/run/current-system/sw/share/sounds/freedesktop/stereo/message-new-instant.oga"' \
        '"${sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message-new-instant.oga"'
  ''
