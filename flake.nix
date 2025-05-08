{
  description = "NixOS configuration (minimal & robust)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    inherit (nixpkgs) lib;

    # Overlays are defined once and exported; they can be reused by other flakes via `inputs.self.overlays`
    overlays = {
      bambustudio = import ./overlays/bambustudio.nix;
    };
  in {
    inherit overlays;

    nixosConfigurations = {
      nixos = lib.nixosSystem {
        system = "x86_64-linux";
        # Expose the entire `inputs` set to all modules
        specialArgs = {inherit inputs;};

        modules = [
          ./system/specialisation.nix

          # Add all declared overlays to nixpkgs
          ({...}: {
            nixpkgs.overlays = builtins.attrValues overlays;
          })
        ];
      };
    };
  };
}
