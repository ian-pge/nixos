{pwaAppIds}: let
  pwaClass = appId: "chrome-${appId}-Default";
  pwaWindowRule = workspace: appId: {
    match.class = "^(${pwaClass appId})$";
    workspace = "special:${workspace}";
  };

  utilityWindowRule = class: width: height: {
    match.class = "^(${class})$";
    float = true;
    center = true;
    size = [width height];
  };
in {
  window_rule = [
    (pwaWindowRule "Chat" pwaAppIds.whatsapp)
    (pwaWindowRule "Chat" pwaAppIds.mattermost)
    (pwaWindowRule "Chat" pwaAppIds.mattermostAlternate)
    (pwaWindowRule "Chat" pwaAppIds.messenger)
    (pwaWindowRule "Chat" pwaAppIds.instagram)
    (pwaWindowRule "Chat" pwaAppIds.telegram)
    (pwaWindowRule "Music" pwaAppIds.spotify)
    (pwaWindowRule "LLM" pwaAppIds.chatgpt)
    (pwaWindowRule "LLM" pwaAppIds.gemini)
    (pwaWindowRule "LLM" pwaAppIds.claude)
    (pwaWindowRule "Notes" pwaAppIds.keep)
    (pwaWindowRule "Agenda" pwaAppIds.calendar)

    (utilityWindowRule "dev\\.me\\.calc" 400 500)
    (utilityWindowRule "dev\\.me\\.file" 1000 600)
    (utilityWindowRule "dev\\.me\\.audio" 1300 500)
    (utilityWindowRule "dev\\.me\\.wifi" 600 800)
    (utilityWindowRule "dev\\.me\\.bluetooth" 600 800)
  ];

  layer_rule = {
    match.namespace = "launcher";
    dim_around = true;
  };
}
