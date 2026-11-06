{pkgs, ...}: let
  applyPerformance = pkgs.writeShellScript "apply-performance-profile" ''
    set -eu

    # ThinkPad firmware profile, independent of the CPU governor.
    echo performance > /sys/firmware/acpi/platform_profile

    # Keep Intel Turbo Boost available, within firmware power/thermal limits.
    echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
    echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct

    # Reapply after resume too. intel_pstate sets EPP to performance with this
    # governor. Leave frequency caps to the firmware and NVIDIA Dynamic Boost.
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
      echo performance > "$policy/scaling_governor"
    done
  '';
in {
  # Make the firmware profile interface available before the service starts.
  boot.kernelModules = ["thinkpad_acpi"];

  # One fixed policy on AC and battery; do not let another manager replace it.
  services.power-profiles-daemon.enable = false;
  services.tlp.enable = false;
  services.auto-cpufreq.enable = false;
  services.tuned.enable = false;

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
    resumeCommands = "${applyPerformance}";
  };

  systemd.services.performance-profile = {
    description = "Apply ThinkPad maximum performance policy";
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service" "cpufreq.service"];
    before = ["nvidia-powerd.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = applyPerformance;
    };
  };
}
