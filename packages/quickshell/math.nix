{
  lib,
  buildNpmPackage,
  nodejs,
  makeWrapper,
}:
buildNpmPackage {
  pname = "quickshell-math";
  version = "0.1.0";
  src = ../../tools/quickshell/math;
  npmDepsHash = "sha256-eYn4avexwUR22cdh3pm5FFYV1uuU2xvuayd+YxV2/60=";
  dontNpmBuild = true;
  nativeBuildInputs = [makeWrapper];
  doCheck = true;
  checkPhase = "node --test test.cjs";
  installPhase = ''
    mkdir -p $out/lib/quickshell-math $out/bin
    cp render.cjs package.json $out/lib/quickshell-math/
    cp -r node_modules $out/lib/quickshell-math/
    makeWrapper ${lib.getExe nodejs} $out/bin/quickshell-math \
      --add-flags "--max-old-space-size=128 $out/lib/quickshell-math/render.cjs"
  '';
}
