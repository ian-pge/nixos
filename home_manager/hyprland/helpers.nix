{lib}: let
  inherit (lib.generators) mkLuaInline;
  toLua = lib.generators.toLua {};

  mkLuaArgs = args: {_args = args;};
  mkBind = key: dispatcher: options:
    mkLuaArgs (
      [
        (mkLuaInline key)
        (mkLuaInline dispatcher)
      ]
      ++ lib.optional (options != {}) options
    );
  mkExec = command: "hl.dsp.exec_cmd(${toLua command})";
  mainKey = key: ''mainMod .. " + ${key}"'';
  plainKey = key: toLua key;
in {
  inherit
    mainKey
    mkBind
    mkExec
    mkLuaArgs
    mkLuaInline
    plainKey
    toLua
    ;
}
