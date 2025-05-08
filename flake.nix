{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    impermanence.url = "github:nix-community/impermanence";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprpanel = {
      url = "github:Jas-SinghFSU/HyprPanel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # `flake-utils` lets us build for every platform in one go
  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      # All overlays – local + upstream – live in ONE list
      overlays = [
        (import ./overlays/bambustudio.nix) # your local overlay
        inputs.hyprpanel.overlay # HyprPanel packages
      ];

      # A pkgs instance with overlays applied
      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
    in {
      # re-export overlays so other flakes can reuse them
      overlays.default = overlays;

      ## ── NixOS host ──────────────────────────────────────────────────
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        specialArgs = {inherit inputs pkgs;};

        modules = [
          ./system/specialisation.nix

          # External modules
          inputs.home-manager.nixosModules.home-manager
          inputs.catppuccin.nixosModules.catppuccin
          inputs.disko.nixosModules.disko
          inputs.impermanence.nixosModules.impermanence
          inputs.hyprpanel.homeManagerModules.hyprpanel

          # Expose overlays to every child module (redundant but harmless)
          ({...}: {nixpkgs.overlays = overlays;})
        ];
      };
    });
}
