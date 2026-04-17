defmodule StellarDAG.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StellarDAGWeb.Telemetry,
      # StellarDAG.Repo,
      {DNSCluster, query: Application.get_env(:stellar_dag, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StellarDAG.PubSub},
      %{
        id: Boltx,
        start: {Boltx, :start_link, [Application.get_env(:boltx, Bolt)] },
      },
      StellarDAG.K8sInformer,
      StellarDAG.Neo4Syncer,
      StellarDAGWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StellarDAG.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StellarDAGWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
