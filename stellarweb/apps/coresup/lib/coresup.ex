defmodule Coresup do
  require Logger

  defp get_active_core_node do
    Node.list()
    |> Enum.filter(&String.starts_with?(to_string(&1), "stellar_core@"))
    |> case do
      [] -> exit(:no_core_nodes_available)
      nodes ->
        Enum.random(nodes)
    end
  end


  def schedule_job(job_name, command_type \\ :bash, content, cron_expr) do
    target_node = get_active_core_node() 
    erlang_payload = {command_type, to_charlist(content)}

    GenServer.call(
      {:job_scheduler, target_node},
      {:schedule, job_name, erlang_payload, cron_expr}
    )
  end

  def execute_now(job_name) do
    target_node = get_active_core_node()
    GenServer.cast({:job_scheduler, target_node}, {:execute_now, job_name})
  end
end

