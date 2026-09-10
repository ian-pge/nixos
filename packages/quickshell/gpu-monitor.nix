{
  writeShellApplication,
  gpuUsage,
}:
writeShellApplication {
  name = "quickshell-gpu-monitor";
  text = ''
    export LD_LIBRARY_PATH=/run/opengl-driver/lib
    exec ${gpuUsage}/bin/gpu-usage-waybar "$@"
  '';
}
