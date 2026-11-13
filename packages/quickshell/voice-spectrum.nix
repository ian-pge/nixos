{lib, writeShellApplication, nodejs, pipewire}: let
  source = lib.fileset.toSource {
    root = ../../tools/quickshell/voice-spectrum;
    fileset = lib.fileset.unions [
      ../../tools/quickshell/voice-spectrum/capture.mjs
      ../../tools/quickshell/voice-spectrum/spectrum.mjs
    ];
  };
in writeShellApplication {
  name = "quickshell-voice-spectrum";
  text = ''
    exec ${nodejs}/bin/node ${source}/capture.mjs ${pipewire}/bin/pw-record
  '';
}
