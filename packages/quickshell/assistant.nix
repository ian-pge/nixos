{
  lib,
  buildGoModule,
  makeWrapper,
  pi,
  # Relative to the home folder; GPT is told to look there for screenshots.
  screenshotsDirectory,
}:
buildGoModule {
  pname = "quickshell-assistant";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/assistant;
    fileset = lib.fileset.fileFilter
      (file: file.hasExt "go" || builtins.elem file.name ["go.mod" "go.sum"])
      ../../tools/quickshell/assistant;
  };
  # Computed from `go mod vendor`; if Nix reports a mismatch, use its value.
  vendorHash = "sha256-8zBX8NEzRfduIYJ2QZMSMwlCUlQaPGxzRfcB6zMhtuc=";
  subPackages = ["."];
  nativeBuildInputs = [makeWrapper];
  # Conversations run through pi; the spelling host never starts it.
  postInstall = ''
    wrapProgram "$out/bin/quickshell-assistant" \
      --set QUICKSHELL_ASSISTANT_PI ${lib.getExe pi} \
      --set QUICKSHELL_ASSISTANT_SCREENSHOTS ${lib.escapeShellArg screenshotsDirectory}
    makeWrapper "$out/bin/quickshell-assistant" "$out/bin/quickshell-spelling-native" \
      --add-flags --correction-native
  '';
  meta = {
    description = "Qwen and OpenAI conversations through pi, and local spelling correction, for Quickshell";
    mainProgram = "quickshell-assistant";
    platforms = lib.platforms.linux;
  };
}
