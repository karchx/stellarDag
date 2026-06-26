defmodule Coresup do
  require Logger


  def schedule_job(job_name, command_type \\ :bash, content, cron_expr) do
    target_node = System.get_env("CORE_NODE", "stellar@stivarch")
    true = Node.connect(@erlang_node)

    erlang_payload = {command_type, to_charlist(content)}

    GenServer.call(
      {:job_scheduler, @erlang_node},
      {:schedule, job_name, erlang_payload, cron_expr}
    )
  end

  def execute_now(job_name) do
    true = Node.connect(@erlang_node)
    GenServer.cast({:job_scheduler, @erlang_node}, {:execute_now, job_name})
  end
end

