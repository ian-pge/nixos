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
    voxtype = {
      url = "github:peteonrails/voxtype";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tabctl = {
      url = "github:slastra/tabctl";
      flake = false;
    };
  };

  outputs = inputs @ {nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    localPackages = import ./packages {inherit inputs pkgs;};
  in {
    packages.${system} = localPackages // {default = localPackages.hyprlockAge;};

    devShells.${system}.rust = import ./dev-shells/rust.nix {inherit pkgs;};

    nixosConfigurations = {
      nixos = lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs localPackages;};

        modules = [
          ./system
        ];
      };
    };
  };
}
