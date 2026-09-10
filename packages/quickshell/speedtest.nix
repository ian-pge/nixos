{
  writeShellApplication,
  coreutils,
  jq,
  ookla-speedtest,
}:
writeShellApplication {
  name = "quickshell-speedtest";
  runtimeInputs = [coreutils jq ookla-speedtest];
  text = builtins.readFile ../../tools/quickshell/speedtest/speedtest.sh;
}
