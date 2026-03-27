defmodule Parselet.Component do
  @moduledoc """
  Defines the behaviour and DSL for Parselet components.
  """

  defmacro __using__(_opts) do
    quote do
      import Parselet.Component
      Module.register_attribute(__MODULE__, :parselet_fields, accumulate: true)
      @before_compile Parselet.Component
    end
  end

  defmacro field(name, opts) do
    quote do
      @parselet_fields {unquote(name), unquote(Macro.escape(opts))}
    end
  end

  defmacro __before_compile__(env) do
    fields =
      Module.get_attribute(env.module, :parselet_fields)
      |> Enum.map(fn {name, opts} ->
        quote do
          {unquote(name), Parselet.Field.new(unquote(name), unquote(opts))}
        end
      end)

    quote do
      def __parselet_fields__ do
        %{
          unquote_splicing(fields)
        }
      end
    end
  end
end
