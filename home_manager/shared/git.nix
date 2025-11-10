{
  programs.git = {
    enable = true;
    settings = {
      user.name = "ian";
      user.email = "ian.page38@gmail.com";
      init.defaultBranch = "main";
      safe.directory = "${../..}";
    };
  };
}
