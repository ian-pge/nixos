{config, localPackages, ...}: {
  # One shared on-demand scan. The shell only receives aggregate byte counts;
  # it never runs as root or obtains access to Docker/VM files.
  systemd.services.quickshell-storage = {
    description = "Read-only disk usage report for Quickshell";
    unitConfig = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 2;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${localPackages.quickshellSystemStats}/bin/quickshell-storage --home ${config.users.users.ian.home} --output /run/quickshell-storage/report.json";
      RuntimeDirectory = "quickshell-storage";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = "yes";
      UMask = "0022";
      TimeoutStartSec = "15min";
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUWeight = 10;
      IOWeight = 10;
      MemoryMax = "1G";
      NoNewPrivileges = true;
      CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = ["/run/quickshell-storage"];
      PrivateDevices = true;
      # Freeze the mount view used by the scanner's mountinfo snapshot.
      MountFlags = "private";
      PrivateNetwork = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      RestrictAddressFamilies = ["AF_UNIX"];
    };
  };

  # Grant only starting this fixed, read-only service to the active local
  # desktop user. No arbitrary units, commands, arguments, or stop operations.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id === "org.freedesktop.systemd1.manage-units"
          && action.lookup("unit") === "quickshell-storage.service"
          && action.lookup("verb") === "start"
          && subject.user === "ian" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';
}
