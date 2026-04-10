defmodule StellarDAG.K8sInformer do
  @moduledoc """
  A GenServer that watches for changes in Kubernetes resources and updates the state of the application accordingly.
  """

  use GenServer
  require Logger

  @pubsub StellarDAG.PubSub
  @topic "workflow"

  def get_jobs do
    GenServer.call(__MODULE__, :get_jobs)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    executable = System.find_executable("stellar") || "/home/stivarch/src/projects/stellarDag/stellardag-core/stellar"

    port = Port.open({:spawn_executable, executable}, [
      :stream,
      :binary,
      :exit_status,
      {:line, 16384},
      args: ["--simple"]
    ])

    {:ok, %{port: port, buffer: "", raw_jobs: %{}}}
  end

  def handle_call(:get_jobs, _from, state) do
    {:reply, Map.values(state.raw_jobs), state}
  end

  def handle_info({port, {:data, {:eol, data}}}, %{port: port} = state) do
    new_state = 
      case Jason.decode(data) do
        {:ok, event} ->
          Phoenix.PubSub.broadcast(@pubsub, @topic, {:k8s_event, event})
          %{state | raw_jobs: Map.put(state.raw_jobs, event["id"], event)}
          
        {:error, reason} ->
          Logger.error("Failed to decode JSON from CLI: #{inspect(reason)}. Raw data: #{data}")
          state
      end

    {:noreply, new_state}
  end

  # MATCH payload exceeding
  def handle_info({port, {:data, {:noeol, data}}}, %{port: port} = state) do
    Logger.error("Received payload exceeding 16KB line limit")
    {:noreply, state}
  end

  def handle_info({ port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Golang Cli exit status: #{status}")

    {:stop, :normal, state}
  end

  defp parse_buffer(buffer) do
    parts = String.split(buffer, "Event: ", trim: true)

    Enum.reduce(parts, {[], ""}, fn part, {events, pending} ->
      clean_part = String.trim(part)

      case Jason.decode(clean_part) do
        {:ok, json} ->
          {events ++ [json], pending}
        {:error, _} ->
          {events, pending <> "Event: " <> part}
      end
    end)
  end
end
