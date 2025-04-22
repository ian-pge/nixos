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
      # Expose the overlay so it can be reused elsewhere
      overlays = {
        devpod = import ./overlays/devpod.nix;
      };
    in
    {
      # Make overlay usable from outside the flake (optional)
      inherit overlays;

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };

        # ←‑‑‑ inject the overlay here
        nixpkgs.overlays = [ overlays.devpod ];

        modules = [
          ./system/specialisation.nix
        ];
      };
    };
}
