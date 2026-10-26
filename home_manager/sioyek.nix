{
  config,
  pkgs,
  ...
}: {
  programs.sioyek = {
    enable = true;

    package = pkgs.sioyek.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        # Qt requests OpenGL ES from NVIDIA EGL unless the app asks for desktop
        # OpenGL explicitly. Sioyek wants a desktop 3.3 Core context, so
        # without this its Wayland window is never drawn (EGL_BAD_MATCH).
        + ''
          for file in pdf_viewer/main.cpp pdf_viewer/pdf_view_opengl_widget.cpp; do
            substituteInPlace "$file" \
              --replace-fail 'format.setProfile(QSurfaceFormat::CoreProfile);' \
                'format.setProfile(QSurfaceFormat::CoreProfile); format.setRenderableType(QSurfaceFormat::OpenGL);'
          done
        '';
    });

    config = {
      check_for_updates_on_startup = "0";
      page_separator_width = "2";
      page_separator_color = "0.5 0.5 0.5";
      # Jump back to the LaTeX source in Zed, even when Sioyek was not opened
      # by Zed (which otherwise passes this command itself).
      inverse_search_command = ''${config.programs.zed-editor.package}/bin/zeditor "%1":%2'';
      # Enter shows the line highlight when it is hidden ([R]) and opens the
      # highlighted line in Zed when it is visible ([r]).
      new_macro = "_highlight_or_open_in_zed [R]enter_visual_mark_mode;[r]synctex_under_ruler";
      # Catppuccin's hex value is rejected because this setting needs RGBA.
      visual_mark_color = "0.502 0.529 0.635 0.2";
      # Animate wheel and keyboard scrolling instead of jumping by fixed steps.
      startup_commands = ["toggle_smooth_scroll_mode"];
    };

    # Vim motions on top of Sioyek's defaults. j/k keep the default
    # move_visual_mark_* commands, which scroll without a line highlight and
    # move the highlight otherwise. The *_smooth commands don't move at all in
    # this build, so they are avoided.
    bindings = {
      move_left = "h";
      move_right = "l";
      screen_down = "<C-d>";
      screen_up = "<C-u>";
      next_page = "d";
      previous_page = "u";

      # Keyboard inverse search: Enter puts the line highlight mid-screen, j/k
      # move it, Enter again opens that line in Zed and Escape removes it.
      _highlight_or_open_in_zed = "<return>";
      close_visual_mark = "<esc>";
    };
  };
}
