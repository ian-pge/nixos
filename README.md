## clone configuration repository
```bash
sudo nix-shell -p git --run "git clone https://github.com/ian-pge/NixOS.git /tmp/NixOS"
```

## disko formatting command
replace `'"/dev/nvme0n1"'` with your drive
```bash
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/NixOS/disko.nix --arg device '"/dev/nvme0n1"'
```

## generate initial config
```bash
sudo nixos-generate-config --no-filesystems --root /mnt
```

## move config
```bash
mv /tmp/NixOS /mnt/etc/nixos
```

## installing nixos
```bash
nixos-install --root /mnt --flake /mnt/etc/nixos#default
```
