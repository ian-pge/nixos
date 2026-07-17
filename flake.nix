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
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wlctl = {
      url = "github:aashish-thapa/wlctl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gazelle-tui = {
      url = "github:Zeus-Deus/gazelle-tui";
      flake = false;
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
      paper-desktop = import ./overlays/paper-desktop.nix;
      # gazelle-tui = final: prev: {
      #   gazelle-tui = (import ./overlays/gazelle-tui.nix final prev).gazelle-tui.overrideAttrs (old: {
      #     src = inputs.gazelle-tui;
      # });
      # };
    };
  in {
    inherit overlays;

    nixosConfigurations = {
      nixos = lib.nixosSystem {
        system = "x86_64-linux";
        # Expose the flake inputs and local overlays to all modules.
        specialArgs = {inherit inputs overlays;};

        modules = [
          ./system/specialisation.nix
        ];
      };
    };
  };
}
