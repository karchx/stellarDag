defmodule StellarDAG.Repo do
  use Ecto.Repo,
    otp_app: :stellar_dag,
    adapter: Ecto.Adapters.Postgres
end
