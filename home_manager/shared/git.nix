{
  programs.git = {
    enable = true;
    userName = "ian";
    userEmail = "ian.page38@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      safe.directory = "${../..}";
    };
  };
}
