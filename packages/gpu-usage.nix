{pkgs}:
pkgs.rustPlatform.buildRustPackage {
  pname = "gpu-usage-waybar";
  version = "v0.1.24";

  src = pkgs.fetchFromGitHub {
    owner = "PolpOnline";
    repo = "gpu-usage-waybar";
    rev = "v0.1.23";
    hash = "sha256-DUIKiUgTy4jn8NZZvjC0zuA993Sbq1Fvr7tvJw3+tNw=";
  };

  cargoHash = "sha256-X3Ak0K1kt7++tE7qZgy8GaRzqemUNTJ3z1yGBJZyA4s=";
  doCheck = false;
}
