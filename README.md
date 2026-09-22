## reference youtube channel
https://youtube.com/@vimjoyer?feature=shared

## clone configuration repository
```bash
sudo nix-shell -p git --run "git clone https://github.com/ian-pge/nixos.git /tmp/nixos"
```

## disko formatting command
replace `'"/dev/nvme0n1"'` with your drive
```bash
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nixos/system/disko.nix --arg device '"/dev/nvme0n1"'
```

## generate initial config
```bash
sudo nixos-generate-config --no-filesystems --root /mnt
```

## replace hardware conf with the generated one
```bash
sudo mv -f /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos/system
sudo rm -r /mnt/etc/nixos
```

## move config
```bash
sudo mv /tmp/nixos /mnt/etc/
```

## installing nixos
```bash
sudo nixos-install --root /mnt --flake /mnt/etc/nixos
```

## updating nixos config
```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

## Workspace navigation

Alt + Super (Cmd) + H/L cycles backwards/forwards through workspaces 1–8,
including empty ones, and wraps at both ends. Focus follows the destination's
monitor: 1–4 on DP-2 and 5–8 on eDP-1 when both are connected. Windows and
workspace assignments are not moved. Special workspaces are excluded; navigation
uses the underlying normal workspace. From an out-of-range workspace, H returns
to 8 and L to 1.

To test the generated bindings without switching the live desktop (requires Lua):

```bash
set -o pipefail
nix eval --raw '.#nixosConfigurations.nixos.config.home-manager.users.ian.xdg.configFile."hypr/hyprland.lua".text' |
  lua home_manager/hyprland/tests/workspace-navigation_test.lua /dev/stdin
```

## Chrome and Surfingkeys

`system/chrome.nix` installs Google Chrome, Surfingkeys and AdBlock through
Chrome's managed policies. These extensions cannot be removed from Chrome's UI
while declared here; Chrome may display "Managed by your organization".
Check `chrome://policy` to see the applied `ExtensionInstallForcelist`.

Home Manager installs `home_manager/surfingkeys.js` as `~/.config/surfingkeys.js`.
After the first rebuild, configure Surfingkeys once per Chrome profile:

1. Open `chrome://extensions/?id=gfbliohnnapiefjpjlpjnehglfpaknnc` and enable
   **Allow access to file URLs** and **Allow User Scripts**.
2. Open `chrome-extension://gfbliohnnapiefjpjlpjnehglfpaknnc/pages/options.html`
   and enable **Advanced mode**. Save any existing custom configuration before
   replacing it with the repository configuration.
3. Set **Load settings from** to `file:///home/ian/.config/surfingkeys.js` and save.
4. Reload a regular web page to check the mappings: `J` selects the next tab,
   `K` the previous tab. Smooth scrolling is disabled and hints align left.
   The UI, link hints and visual mode use Catppuccin Macchiato with a Sapphire accent.

Edit the repository's JavaScript file and rebuild for subsequent changes.
If Chrome keeps using an older configuration, save the settings URL again and
reload the page. The existing persistence of `.config/google-chrome` retains
the profile's setup across reboots.
