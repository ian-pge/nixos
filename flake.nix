{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    disko.url = "github:nix-community/disko";
    impermanence.url = "github:nix-community/impermanence";
    home-manager.url = "github:nix-community/home-manager";
    catppuccin.url = "github:catppuccin/nix";
    hyprpanel.url = "github:Jas-SinghFSU/HyprPanel";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    disko,
    impermanence,
    home-manager,
    catppuccin,
    hyprpanel,
    ...
  }: {
    # overlays visible to outside users (optional)
    overlays.default = [
      (import ./overlays/bambustudio.nix)
      hyprpanel.overlay
    ];

    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      nixpkgs.overlays = self.overlays.default;
      specialArgs = {inherit inputs;};

      modules = [
        ./system/specialisation.nix
      ];
    };
  };
}
