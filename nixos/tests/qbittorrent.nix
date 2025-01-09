import ./make-test-python.nix ({pkgs, ...}: {
  name = "qbittorrent";
  meta = with pkgs.lib.maintainers; {
    maintainers = [ fsnkty ];
  };

  nodes = {
    simple = {
      services.qbittorrent.enable = true;
    };
    declarative = {
      services.qbittorrent = {
        enable = true;
        webuiPort = 8181;
        openFirewall = true;
        serverConfig = {
          LegalNotice.Accepted = true;
          Preferences = {
            WebUI.Username = "user";
            General.Locale = "en";
          };
        };
        # torrenting-port can also be set through the torrentingPort module option.
        # We set it this way to make it easy to test extraArgs
        extraArgs = [ "--torrenting-port=55555" ];
      };
    };
  };

  testScript = ''
    start_all()

    simple.wait_for_unit("qbittorrent.service")
    simple.wait_for_open_port(8080)
    simple.wait_until_succeeds("curl --fail http://localhost:8080")

    declarative.wait_for_unit("qbittorrent.service")
    declarative.wait_for_open_port(8181)
    declarative.wait_for_open_port(55555)
    declarative.wait_for_console_text("The WebUI administrator username is: user")
    declarative.wait_until_succeeds("curl --fail http://localhost:8181")
    simple.wait_until_succeeds("curl --fail http://declarative:8181")
  '';
})
