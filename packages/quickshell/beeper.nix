{
  lib,
  buildGoModule,
  dbus,
  makeWrapper,
  libsecret,
  wl-clipboard,
  xdg-utils,
}:
buildGoModule {
  pname = "quickshell-beeper";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/beeper;
    fileset = lib.fileset.fileFilter
      (file: file.hasExt "go" || builtins.elem file.name ["go.mod" "go.sum"])
      ../../tools/quickshell/beeper;
  };
  vendorHash = "sha256-zGPpM5JFhrfRYyGPKyI3kSg9sYjxuUmSZPOQXp/+m1Y=";
  subPackages = ["."];
  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [dbus];
  postInstall = ''
    wrapProgram "$out/bin/quickshell-beeper" \
      --prefix PATH : ${lib.makeBinPath [libsecret wl-clipboard xdg-utils]}
  '';
  meta = {
    description = "Beeper Desktop API client for Quickshell";
    mainProgram = "quickshell-beeper";
    platforms = lib.platforms.linux;
  };
}
