{
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "image/png" = "oculante.desktop";
      "image/jpeg" = "oculante.desktop";
      "image/gif" = "oculante.desktop";
      "image/svg+xml" = "oculante.desktop";
      "image/bmp" = "oculante.desktop";
      "image/webp" = "oculante.desktop";
      "application/pdf" = "org.pwmt.zathura-pdf-mupdf.desktop";
      "inode/directory" = "dev.zed.Zed.desktop";
      "inode/mount-point" = "dev.zed.Zed.desktop";
      "text/plain" = "dev.zed.Zed.desktop";
      "text/markdown" = "dev.zed.Zed.desktop";
      "text/x-nix" = "dev.zed.Zed.desktop";
      "application/json" = "dev.zed.Zed.desktop";
      "application/toml" = "dev.zed.Zed.desktop";
      "application/yaml" = "dev.zed.Zed.desktop";
      "application/x-yaml" = "dev.zed.Zed.desktop";
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/mpeg" = "mpv.desktop";
    };
    addedAssociations = {
      # "inode/directory" = "comsic-files.desktop";
    };
  };
}
