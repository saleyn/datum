defmodule Parselet.Component do
  @moduledoc """
  Defines the behaviour and DSL for Parselet components.

  Components can define fields with `field/2` and can optionally provide a
  `preprocess/1` hook to normalize or transform the raw text before field-level
  parsing is performed.
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

  @doc """
  Define a preprocessing function for the component.

  The supplied function is invoked once with the raw text and the returned text
  is used for all subsequent field extraction within that component.

  You can pass the function directly:

      preprocess &String.upcase/1

  or via keyword syntax:

      preprocess function: &String.upcase/1
  """
  defmacro preprocess(opts) do
    quote do
      @parselet_preprocess unquote(Macro.escape(opts))
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

    preprocess =
      case Module.get_attribute(env.module, :parselet_preprocess) do
        nil -> nil
        opts when is_list(opts) ->
          if Keyword.has_key?(opts, :function) do
            Keyword.fetch!(opts, :function)
          else
            opts
          end

        opts -> opts
      end

    quote do
      def __parselet_fields__ do
        %{
          unquote_splicing(fields)
        }
      end

      def __parselet_preprocess__ do
        unquote(preprocess)
      end
    end
  end
end
