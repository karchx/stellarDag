defmodule StellarDAGWeb.PageController do
  use StellarDAGWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
