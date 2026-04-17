defmodule StellarDAG.Neo4Syncer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    Phoenix.PubSub.subscribe(StellarDAG.PubSub, "workflow")
    {:ok, %{}}
  end

  def handle_info({:k8s_event, incoming_job}, state) do
    job = %{
      id: incoming_job["id"],
      name: incoming_job["name"],
      namespace: incoming_job["namespace"],
      image: incoming_job["image"],
      status: incoming_job["status"],
      predecessors: incoming_job["predecessors"] || [],
      x: incoming_job["x"],
      y: incoming_job["y"]
    }

    StellarDAG.GraphDB.upsert_job(job)
    {:noreply, state}
  end

  def handle_info({:add_connection, from_id, to_id}, state) do
    StellarDAG.GraphDB.add_dependency(to_id, from_id)
    {:noreply, state}
  end

  def handle_info({:remove_connection, from_id, to_id}, state) do
    StellarDAG.GraphDB.remove_dependency(to_id, from_id)
    {:noreply, state}
  end

  def handle_info({:update_node_position, id, x, y}, state) do
    query = "MATCH (j:Job {id: $id}) SET j.x = $x, j.y = $y"
    Boltx.query!(Bolt, query, %{"id" => id, "x" => x, "y" => y})
    {:noreply, state}
  end

  def handle_info({:sync_jobs, _}, state), do: {:noreply, state}
  def handle_info(_, state), do: {:noreply, state}
end
