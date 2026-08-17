{
  helpers,
  voxtypePackage,
}: let
  inherit (helpers) mkBind mkExec plainKey;
in {
  voxtype = {
    onDispatch = "reset";
    settings.bind = [
      (mkBind
        (plainKey "ESCAPE")
        (mkExec "${voxtypePackage}/bin/voxtype record cancel")
        {ignore_mods = true;})
    ];
  };
}
