final: prev: let
  pname = "paper-desktop";
  version = "0.4.4";
  src = final.fetchurl {
    url = "https://download.paper.design/linux/appImage";
    name = "${pname}-${version}-x86_64.AppImage";
    hash = "sha256-x1Zs9OW8+V1zYBf5zAq2V7HeaYyE0rwza59OpSgwRJc=";
  };
  appimageContents = final.appimageTools.extractType2 {
    inherit pname version src;
  };
in {
  paper-desktop = final.appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/${pname}.desktop \
        $out/share/applications/${pname}.desktop
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' "Exec=$out/bin/${pname} --no-sandbox %U"
      cp -r ${appimageContents}/usr/share/icons $out/share/
    '';

    meta = {
      description = "Paper Desktop design app";
      homepage = "https://paper.design";
      license = final.lib.licenses.unfree;
      mainProgram = pname;
      platforms = ["x86_64-linux"];
    };
  };
}
