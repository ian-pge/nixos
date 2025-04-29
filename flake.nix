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

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    # Expose the overlay so it can be reused elsewhere
    overlays = {
      devpod = import ./overlays/devpod.nix;
      bambustudio = import ./overlays/bambustudio.nix;
      xdg = import ./overlays/xdg_termfilechooser.nix;
    };
  in {
    # Make overlay usable from outside the flake (optional)
    inherit overlays;

    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ({...}: {
          nixpkgs.overlays = [
            overlays.devpod
            overlays.bambustudio
            overlays.xdg
          ];
        })
        ./system/specialisation.nix
      ];
    };
  };
}
