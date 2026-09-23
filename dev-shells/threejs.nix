{pkgs}:
pkgs.mkShell {
  # Node includes npm. Three.js, Vite, TypeScript and test tooling belong to
  # each project's package.json / package-lock.json, not a global install.
  packages = [pkgs.nodejs];
}
