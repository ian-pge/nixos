## clone configuration repository
```bash
sudo nix-shell -p git --run "git clone https://github.com/ian-pge/nixos.git /tmp/nixos"
```

## disko formatting command
replace `'"/dev/nvme0n1"'` with your drive
```bash
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nixos/system/shared/disko.nix --arg device '"/dev/nvme0n1"'
```

## generate initial config
```bash
sudo nixos-generate-config --no-filesystems --root /mnt
```

## replace hardware conf with the generated one
```bash
sudo mv -f /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos/system/shared
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
