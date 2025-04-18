## clone configuration repository
```bash
sudo nix-shell -p git --run "git clone https://github.com/ian-pge/nixos.git /tmp/nixos"
```

## disko formatting command
replace `'"/dev/nvme0n1"'` with your drive
```bash
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nixos/disko.nix --arg device '"/dev/nvme0n1"'
```

## optional generate initial config
```bash
sudo nixos-generate-config --no-filesystems --root /mnt
```

## move config
```bash
sudo mv /tmp/nixos /etc/nixos
```

## installing nixos
```bash
sudo nixos-install --root /mnt --flake /mnt/etc/nixos#default
```

## updating nixos config
```bash
sudo nixos-rebuild switch --flake /etc/nixos#default
```
