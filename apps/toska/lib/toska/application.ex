defmodule Toska.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the configuration manager
      Toska.ConfigManager,
      # The server will be started on demand via CLI commands
      # {Toska.Server, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Toska.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
