{pkgs, ...}: {
  systemd.user.services.playwright-mcp = {
    Unit = {
      Description = "Visible Playwright MCP server for Zed agents";
      Documentation = ["https://github.com/microsoft/playwright-mcp#standalone-mcp-server"];
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${pkgs.playwright-mcp}/bin/playwright-mcp --host 127.0.0.1 --port 8931 --isolated --output-mode=stdout --viewport-size=1440x900";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install.WantedBy = ["graphical-session.target"];
  };
}
