defmodule Openrouter.Client do
  @moduledoc """
  Client configuration and state.

  The client holds configuration for making requests to AI providers.
  """

  @type t :: %__MODULE__{
          provider: module(),
          config: map(),
          model: String.t() | nil,
          timeout: pos_integer()
        }

  defstruct [
    :provider,
    :config,
    :model,
    timeout: 60_000
  ]

  @doc """
  Creates a new client.

  ## Options

    * `:provider` - Provider module (default: `Openrouter.Provider.OpenRouter`)
    * `:model` - Default model to use (e.g., "anthropic/claude-sonnet-4-0")
    * `:api_key` - API key for authentication
    * `:base_url` - Base URL for the API
    * `:timeout` - Request timeout in milliseconds (default: 60_000)
    * `:app_name` - Application name for OpenRouter tracking
    * `:site_url` - Site URL for OpenRouter tracking

  ## Examples

      iex> Openrouter.Client.new()
      %Openrouter.Client{provider: Openrouter.Provider.OpenRouter, ...}

      iex> Openrouter.Client.new(model: "openai/gpt-4", api_key: "sk-...")
      %Openrouter.Client{model: "openai/gpt-4", ...}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    provider = Keyword.get(opts, :provider, default_provider())
    config = build_config(provider, opts)

    %__MODULE__{
      provider: provider,
      config: config,
      model: Keyword.get(opts, :model) || config[:default_model],
      timeout: Keyword.get(opts, :timeout, 60_000)
    }
  end

  @doc """
  Updates the client configuration.
  """
  @spec put_config(t(), atom(), any()) :: t()
  def put_config(%__MODULE__{} = client, key, value) do
    %{client | config: Map.put(client.config, key, value)}
  end

  @doc """
  Gets a configuration value.
  """
  @spec get_config(t(), atom(), any()) :: any()
  def get_config(%__MODULE__{} = client, key, default \\ nil) do
    Map.get(client.config, key, default)
  end

  # Private helpers

  defp default_provider do
    Openrouter.Provider.OpenRouter
  end

  defp build_config(provider, opts) do
    # Get default config from application environment
    app_config = Application.get_env(:openrouter, :config, %{})

    # Merge with provider-specific config
    provider_config =
      case provider do
        Openrouter.Provider.OpenRouter ->
          build_openrouter_config(opts, app_config)

        _ ->
          %{}
      end

    Map.merge(app_config, provider_config)
  end

  defp build_openrouter_config(opts, app_config) do
    %{
      api_key: get_config_value(opts, app_config, :api_key),
      base_url:
        get_config_value(opts, app_config, :base_url, "https://openrouter.ai/api/v1"),
      app_name: get_config_value(opts, app_config, :app_name),
      site_url: get_config_value(opts, app_config, :site_url),
      default_model: get_config_value(opts, app_config, :default_model)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp get_config_value(opts, app_config, key, default \\ nil) do
    Keyword.get(opts, key) || Map.get(app_config, key) || default
  end
end
