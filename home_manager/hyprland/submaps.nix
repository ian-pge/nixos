{
  helpers,
  voxtypePackage,
}: let
  inherit (helpers) mkBind plainKey toLua;
in {
  voxtype = {
    settings.bind = [
      (mkBind
        (plainKey "ESCAPE")
        ''function()
          if quickshell_dismiss_notification() then
            return
          end
          hl.exec_cmd(${toLua "${voxtypePackage}/bin/voxtype record cancel"})
          hl.dispatch(hl.dsp.submap("reset"))
        end''
        {ignore_mods = true;})
    ];
  };
}
