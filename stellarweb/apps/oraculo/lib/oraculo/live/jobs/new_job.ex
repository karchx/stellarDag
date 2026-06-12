defmodule Oraculo.NewJob do

  use Oraculo, :live_component
  alias Ecto.Changeset

  @types %{job_name: :string, type_job: :string, content: :string, cron: :string}

  def update(_assigns, socket) do
    # Init empty form
    changeset = Changeset.cast({%{}, @types}, %{}, [])
    {:ok, assign(socket, form: to_form(changeset, as: :job), jobs: [])}
  end

  def handle_event("save_job", %{"job" => params}, socket) do
    changeset = 
      {%{}, @types}
      |> Changeset.cast(params, Map.keys(@types))
      |> Changeset.validate_required([:job_name, :type_job, :content, :cron])

    if changeset.valid? do
      %{job_name: job_name, type_job: type_job, content: content, cron: cron} = Changeset.apply_changes(changeset)

      case Coresup.schedule_job(job_name, type_job, content, cron) do
        {:ok, job_id} ->
          new_job = %{
            id: job_id, 
            job_name: job_name, 
            type_job: type_job, 
            content: content, 
            cron: cron, 
            status: "in_queue",
            namespace: "default",
            image: "unknown",
            x: 500,
            y: 500
          }
          send(self(), {:job_created, new_job})

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      # Show form with message errors
      {:noreply, assign(socket, form: to_form(changeset, as: :job))}
    end
  end
end
