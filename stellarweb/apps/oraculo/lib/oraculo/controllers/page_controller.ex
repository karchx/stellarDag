defmodule Oraculo.PageController do
  use Oraculo, :controller

  def home(conn, _params) do
    conn
    |> assign(:form_data, %{"jobName" => "", "typeJob" => "", "content" => "", "cron" => ""})
    |> render(:home)
  end
end
