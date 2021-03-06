defmodule OpenAperture.Messaging.Mixfile do
  use Mix.Project

  def project do
    [app: :openaperture_messaging,
     version: "0.0.1",
     elixir: "~> 1.0",
     elixirc_paths: ["lib"],
     escript: [main_module: OpenAperture.Messaging],
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      mod: { OpenAperture.Messaging, [] },
      applications: [:logger, :openaperture_manager_api, :amqp]
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
      {:ex_doc, "0.7.3", only: :test},
      {:earmark, "0.1.17", only: :test},
      {:amqp, "0.1.1"},
      {:uuid, "~> 0.1.5" },

      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "7bee243e9ae57938b09799ac01a9edc2f722720c"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", only: :test},
      {:meck, "0.8.2", only: :test}
    ]
  end
end
