{ pkgs, lib, inputs, ... }:

{
    imports =
    [
        ./hardware-configuration.nix
        (import ./disko.nix { device = "/dev/nvme0n1"; })
        inputs.disko.nixosModules.default
        inputs.impermanence.nixosModules.impermanence
        inputs.home-manager.nixosModules.default
    ];

    boot.loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
    };

    # boot = {
        # kernelParams = [ "snd_intel_dspcfg.dsp_driver=1" ];
        # optionally also
        # kernelPackages = pkgs.linuxPackages_6_8;
    # };

    boot.initrd.postDeviceCommands = lib.mkAfter ''
        mkdir /btrfs_tmp
        mount /dev/root_vg/root /btrfs_tmp
        if [[ -e /btrfs_tmp/root ]]; then
            mkdir -p /btrfs_tmp/old_roots
            timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
            mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
        fi

        delete_subvolume_recursively() {
            IFS=$'\n'
            for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                delete_subvolume_recursively "/btrfs_tmp/$i"
            done
            btrfs subvolume delete "$1"
        }

        for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
            delete_subvolume_recursively "$i"
        done

        btrfs subvolume create /btrfs_tmp/root
        umount /btrfs_tmp
    '';

    fileSystems."/persist".neededForBoot = true;
    environment.persistence."/persist/system" = {
        hideMounts = true;
        directories = [
            "/etc/nixos"
            "/var/log"
            "/var/lib/bluetooth"
            "/var/lib/nixos"
            "/var/lib/systemd/coredump"
            "/var/lib/docker"
            "/var/cache/tuigreet"
            "/etc/NetworkManager/system-connections"
            { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
        ];
        files = [
            "/etc/machine-id"
            { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
        ];
    };

    systemd.tmpfiles.rules = [
        "d /persist/home 0777 root root -"
        "d /persist/home/ian 0700 ian users -"
    ];

    system.stateVersion = "24.11";

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    time.timeZone = "Europe/Paris";

    users.users."ian" = {
        isNormalUser = true;
        initialPassword = "ianbage";
        extraGroups = [ "wheel" "docker" "video" ]; # Enable ‘sudo’ for the user.
    };

    hardware.keyboard.qmk.enable = true;

    programs = {
        fuse.userAllowOther = true;
        dconf.enable = true;
        nh = {
            enable = true;
            clean.enable = true;
            clean.extraArgs = "--keep-since 4d --keep 3";
            flake = "/etc/nixos";
        };
    };

    services.udev.extraRules = ''
        ${builtins.readFile ../material/99-slabs.rules}
      '';

    services.udev.packages = [ pkgs.via ];

    services = {
        openssh.enable = true;
    };

    hardware.nvidia-container-toolkit.enable = true;

    virtualisation.docker = {
        enable = true;
        storageDriver = "btrfs";
    };

    nixpkgs.config.allowUnfree = true;

    # Packages
    environment.systemPackages = with pkgs; [
        zed-editor
        devpod
        bambu-studio
        clang-tools
        package-version-server
        kitty
        git
        google-chrome
        blender

        (python3.withPackages (ps: with ps; [
            python-lsp-server
            python-lsp-jsonrpc
            python-lsp-black
            pyls-isort
            pyls-flake8
        ]))
        black
        nil
        nixd
        alejandra
        nvd
        nix-output-monitor
        via
    ];

}
