defmodule Oraculo.PageController do
  use Oraculo, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
