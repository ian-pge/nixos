{pkgs, ...}: {
  systemd.user.services.chezmoi-apply = {
    Unit = {
      Description = "Apply chezmoi dotfiles";
    };

    Service = {
      Type = "oneshot";
      ExecCondition = "${pkgs.bash}/bin/bash -c 'test -d \"$HOME/.local/share/chezmoi\" || test -f \"$HOME/.config/chezmoi/chezmoi.toml\"'";
      ExecStart = "${pkgs.chezmoi}/bin/chezmoi apply --force --no-tty";
    };

    Install = {
      WantedBy = ["default.target"];
    };
  };
}
