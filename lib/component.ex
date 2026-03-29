defmodule Parselet.Component do
  @moduledoc """
  Defines the behaviour and DSL for Parselet components.

  Components can define fields with `field/2` and can optionally provide a
  `preprocess/1` hook to normalize or transform the raw text before field-level
  parsing is performed. Components can also define a `postprocess/1` hook that
  runs after all fields are extracted. Each component module also gains `parse/2`
  and `parse!/2` convenience functions to parse input directly into the
  corresponding struct.
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

      preprocess fn text ->
        String.upcase(text)
      end

  or via shorthand function capture:

      preprocess &String.upcase/1
  """
  defmacro preprocess(opts) do
    quote do
      @parselet_preprocess unquote(Macro.escape(opts))
    end
  end

  @doc """
  Define a postprocessing function for the component.

  After all fields have been extracted, this function is invoked once with the
  map of parsed values. It must return either `:ok` or a map. When a map is
  returned, its contents are merged into the parsed result.

  You can pass the function directly:

      postprocess &add_metadata/1

  or via keyword syntax:

      postprocess function: &add_metadata/1
  """
  defmacro postprocess(opts) do
    quote do
      @parselet_postprocess unquote(Macro.escape(opts))
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
          raise ArgumentError,
                "preprocess keyword syntax is no longer supported; use preprocess &fun/1 or preprocess fn text -> ... end"

        opts -> opts
      end

    postprocess =
      case Module.get_attribute(env.module, :parselet_postprocess) do
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

      def __parselet_postprocess__ do
        unquote(postprocess)
      end

      def parse(text, opts \\ []) do
        Parselet.parse(text, Keyword.put(opts, :structs, [__MODULE__]))
      end

      def parse!(text, opts \\ []) do
        Parselet.parse!(text, Keyword.put(opts, :structs, [__MODULE__]))
      end
    end
  end
end
