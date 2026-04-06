defmodule StellarDAGWeb.WorkflowLive do
  use StellarDAGWeb, :live_view

  @initial_jobs [
    %{id: "1", name: "gaia_source", namespace: "ds", image: "go-parquet:1.0.0", status: "completed", predecessors: [], x: 80, y: 120},
    %{id: "2", name: "gaia_source_aws", namespace: "ds", image: "go-parquet:1.0.0", status: "completed", predecessors: [], x: 380, y: 60},
    %{id: "4", name: "nfss", namespace: "ds", image: "go-parquet:1.0.0", status: "completed", predecessors: ["1", "2"], x: 680, y: 140},
  ]

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(StellarDAG.PubSub, "workflow")
    {:ok, assign(socket, jobs: @initial_jobs, zoom: 1.0, pan_x: 0, pan_y: 0, show_dialog: false)}
  end

  def handle_info({:sync_jobs, updated_jobs}, socket) do
    {:noreply, assign(socket, jobs: updated_jobs)}
  end

  def handle_event("update_node_position", %{"id" => id, "x" => x, "y" => y}, socket) do
    jobs = Enum.map(socket.assigns.jobs, fn
      %{id: ^id} = job -> %{job | x: max(0, round(x)), y: max(0, round(y))}
      job -> job
    end)
    Phoenix.PubSub.broadcast(StellarDAG.PubSub, "workflow", {:sync_jobs, jobs})
    {:noreply, assign(socket, jobs: jobs)}
  end

  def handle_event("add_connection", %{"from" => from_id, "to" => to_id}, socket) do
    jobs = Enum.map(socket.assigns.jobs, fn job ->
      if job.id == to_id and from_id not in job.predecessors do
        %{job | predecessors: job.predecessors ++ [from_id]}
      else
        job
      end
    end)

    Phoenix.PubSub.broadcast(StellarDAG.PubSub, "workflow", {:sync_jobs, jobs})
    {:noreply, assign(socket, jobs: jobs)}
  end

  def handle_event("update_viewport", %{"pan_x" => px, "pan_y" => py, "zoom" => zoom}, socket) do
    {:noreply, assign(socket, pan_x: px, pan_y: py, zoom: zoom)}
  end

  def handle_event("remove_connection", %{"from" => from_id, "to" => to_id}, socket) do
    jobs = Enum.map(socket.assigns.jobs, fn job ->
      if job.id == to_id do
        %{job | predecessors: Enum.reject(job.predecessors, &(&1 == from_id))}
      else
        job
      end
    end)

    Phoenix.PubSub.broadcast(StellarDAG.PubSub, "workflow", {:sync_jobs, jobs})
    {:noreply, assign(socket, jobs: jobs)}
  end

  def handle_event("open_dialog", _, socket), do: {:noreply, assign(socket, show_dialog: true)}
  def handle_event("close_dialog", _, socket), do: {:noreply, assign(socket, show_dialog: false)}

  def handle_event("save_job", %{"job" => job_params}, socket) do
    new_job = %{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(),
      name: job_params["name"],
      namespace: job_params["namespace"],
      image: job_params["image"],
      status: job_params["status"],
      predecessors: Map.get(job_params, "predecessors", []),
      x: 100,
      y: 100
    }

    jobs = socket.assigns.jobs ++ [new_job]
    Phoenix.PubSub.broadcast(StellarDAG.PubSub, "workflow", {:sync_jobs, jobs})
    {:noreply, assign(socket, jobs: jobs, show_dialog: false)}
  end

  defp status_color("pending"), do: {"text-yellow-500", "bg-yellow-500/20"}
  defp status_color("running"), do: {"text-blue-500", "bg-blue-500/20"}
  defp status_color("completed"), do: {"text-green-500", "bg-green-500/20"}
  defp status_color("failed"), do: {"text-red-500", "bg-red-500/20"}

  defp get_connections(jobs) do
    for job <- jobs,
        pred_id <- job.predecessors,
        pred = Enum.find(jobs, &(&1.id == pred_id)),
        not is_nil(pred) do
      %{id: "#{pred.id}-#{job.id}", from: pred, to: job}
    end
  end

  defp bezier_path(from_job, to_job) do
    start_x = from_job.x + 224
    start_y = from_job.y + 60
    end_x = to_job.x
    end_y = to_job.y + 60

    cp1_x = start_x + abs(end_x - start_x) * 0.4
    cp2_x = end_x - abs(end_x - start_x) * 0.4

    "M #{start_x} #{start_y} C #{cp1_x} #{start_y}, #{cp2_x} #{end_y}, #{end_x} #{end_y}"
  end
end
