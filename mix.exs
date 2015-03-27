defmodule CloudOS.Messaging.Mixfile do
  use Mix.Project

  def project do
    [app: :cloudos_messaging,
     version: "0.0.1",
     elixir: "~> 1.0",
     elixirc_paths: ["lib"],
     escript: [main_module: CloudOS.Messaging],
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      mod: { CloudOS.Messaging, [] },
      applications: [:logger, :cloudos_manager_api]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:amqp, "0.1.0"},
      {:uuid, "~> 0.1.5" },

      {:cloudos_manager_api, git: "https://#{System.get_env("GITHUB_OAUTH_TOKEN")}:x-oauth-basic@github.com/UmbrellaCorporation-SecretProjectLab/cloudos_manager_api.git", ref: "2c9d20d705dc94580699f56c539dbf64746ffaf5"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr"},
      {:meck, "0.8.2"}
    ]
  end
end
