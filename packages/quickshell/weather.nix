{
  writeShellApplication,
  wttrbar,
}:
writeShellApplication {
  name = "quickshell-weather";
  runtimeInputs = [wttrbar];
  text = ''
    exec wttrbar --nerd "$@"
  '';
}
