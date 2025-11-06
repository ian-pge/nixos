{
  description = "NixOS configuration (minimal & robust)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
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
    nextmeeting = {
      url = "github:chmouel/nextmeeting?dir=packaging";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # hyprpanel = {
    #   url = "github:Jas-SinghFSU/HyprPanel";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    gazelle-src.url = "github:Zeus-Deus/gazelle-tui";
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
      gazelle = import ./overlays/gazelle-tui.nix {inherit inputs;};
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
            nixpkgs.overlays = builtins.attrValues overlays; #++ [inputs.hyprpanel.overlay];
          })
        ];
      };
    };
  };
}
