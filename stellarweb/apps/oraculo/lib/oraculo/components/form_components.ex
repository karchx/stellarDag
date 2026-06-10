defmodule Oraculo.FormComponents do
  use Phoenix.Component

  # @inputs() component
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :type, :string, default: "text"

  def input(assigns) do
    ~H"""
      <div>
        <label class="block text-sm font-medium mb-1"><%= @label %></label>
        <input
           type={@type}
           name={@name}
           value={@value}
           class="w-full bg-gray-950 border border-gray-800 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-blue-500"
        />
      </div>
    """
  end
end
