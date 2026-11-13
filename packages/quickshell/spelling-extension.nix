{
  runCommand,
  quickshellAssistant,
}: let
  extensionId = builtins.replaceStrings ["\n"] [""] (builtins.readFile ../../tools/quickshell/spelling-extension/extension-id);
  host = builtins.toJSON {
    name = "com.quickshell.spelling";
    description = "Qwen local spelling correction";
    path = "${quickshellAssistant}/bin/quickshell-spelling-native";
    type = "stdio";
    allowed_origins = ["chrome-extension://${extensionId}/"];
  };
in
  runCommand "quickshell-spelling-extension" {passthru = {inherit extensionId;};} ''
    mkdir -p $out/extension $out/native-messaging
    cp ${../../tools/quickshell/spelling-extension}/{manifest.json,background.js,editor.js,content.js,popup.html} $out/extension/
    cat > $out/native-messaging/com.quickshell.spelling.json <<'JSON'
    ${host}
    JSON
  ''
