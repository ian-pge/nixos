{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
      let
        system = "x86_64-linux";

        # 1) bring in our overlay
        overlays = [ (import ./overlays/devpod.nix) ];

        # 2) re‑import nixpkgs with overlays
        pkgs = import nixpkgs {
          inherit system;
          overlays = overlays;
        };
      in
      {
        nixosConfigurations.nixos = pkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs pkgs; };
          modules = [
            ./system/specialisation.nix
          ];
        };
      };
}
