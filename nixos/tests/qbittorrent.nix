import ./make-test-python.nix (
  { pkgs, ... }:
  {
    name = "qbittorrent";

    meta = with pkgs.lib.maintainers; {
      maintainers = [ fsnkty ];
    };

    nodes = {
      simple = {
        services.qbittorrent = {
          enable = true;
          openFirewall = true;
        };
      };
      declarative = {
        services.qbittorrent = {
          enable = true;
          webuiPort = null;
          serverConfig = {
            LegalNotice.Accepted = true;
            Preferences = {
              WebUI = {
                Username = "user";
                # Default password: adminadmin
                Password_PBKDF2 = "@ByteArray(6DIf26VOpTCYbgNiO6DAFQ==:e6241eaAWGzRotQZvVA5/up9fj5wwSAThLgXI2lVMsYTu1StUgX9MgmElU3Sa/M8fs+zqwZv9URiUOObjqJGNw==)";
                Port = "8181";
              };
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
      simple.start(allow_reboot=True)
      declarative.start(allow_reboot=True)


      def test_webui(machine, port):
          machine.wait_for_unit("qbittorrent.service")
          machine.wait_for_open_port(port)
          machine.wait_until_succeeds(f"curl --fail http://localhost:{port}")


      # To simulate an interactive change in the settings
      def setPreferences_api(machine, port, post_creds, post_data):
          qb_url = f"http://localhost:{port}"
          api_url = f"{qb_url}/api/v2"
          cookie_path = "/tmp/qbittorrent.cookie"

          machine.succeed(
              f'curl --header "Referer: {qb_url}" \
              --data "{post_creds}" {api_url}/auth/login \
              -c {cookie_path}'
          )
          machine.succeed(
              f'curl --header "Referer: {qb_url}" \
              --data "{post_data}" {api_url}/app/setPreferences \
              -b {cookie_path}'
          )


      # A randomly generated password is printed in the service log when no
      # password it set
      def get_temp_pass(machine):
          _, password = machine.execute(
              "journalctl -u qbittorrent.service |\
        grep 'The WebUI administrator password was not set.' |\
        awk '{ print $NF }' | tr -d '\n'"
          )
          return password


      # Test simple VM
      test_webui(simple, 8080)

      ## Test if firewall is opened correctly
      declarative.wait_until_succeeds("curl --fail http://simple:8080")

      ## Change some settings
      simple_pass = get_temp_pass(simple)

      setPreferences_api(
          machine=simple,
          port=8080,
          post_creds=f"username=admin&password={simple_pass}",
          post_data=r"json={\"listen_port\": 33333}",
      )
      setPreferences_api(
          machine=simple,
          port=8080,
          post_creds=f"username=admin&password={simple_pass}",
          post_data=r"json={\"web_ui_port\": 9090}",
      )

      simple.wait_for_open_port(33333)
      test_webui(simple, 9090)

      ## Test which settings are reset
      ## As webuiPort is passed as an cli it should reset after reboot
      ## As torrentingPort is not passed as an cli it should not reset after
      ## reboot
      simple.reboot()
      test_webui(simple, 8080)
      simple.wait_for_open_port(33333)


      # Test declarative VM
      test_webui(declarative, 8181)
      declarative.wait_for_open_port(55555)

      ## Change some settings
      setPreferences_api(
          machine=declarative,
          port=8181,  # as set through serverConfig
          post_creds="username=user&password=adminadmin",
          post_data=r"json={\"web_ui_port\": 9191}",
      )

      test_webui(declarative, 9191)

      ## Test which settings are reset
      ## The generated qBittorrent.conf is, apparently, reapplied after reboot.
      ## Because the port is set in `serverConfig` this overrides the manually
      ## set port.
      declarative.reboot()
      test_webui(declarative, 8181)
    '';
  }
)
