defmodule Openrouter.Config do
  @moduledoc """
  Configuration handling and validation.

  This module provides utilities for managing configuration across
  the application and runtime.
  """

  @doc """
  Gets the API key from config or environment.

  Priority:
  1. Explicitly passed api_key
  2. Application config
  3. OPENROUTER_API_KEY environment variable
  """
  @spec get_api_key(String.t() | nil) :: String.t() | nil
  def get_api_key(api_key \\ nil) do
    api_key ||
      get_app_config(:api_key) ||
      System.get_env("OPENROUTER_API_KEY")
  end

  @doc """
  Gets the base URL from config or environment.
  """
  @spec get_base_url(String.t() | nil) :: String.t()
  def get_base_url(base_url \\ nil) do
    base_url ||
      get_app_config(:base_url) ||
      System.get_env("OPENROUTER_BASE_URL") ||
      "https://openrouter.ai/api/v1"
  end

  @doc """
  Gets the default model from config.
  """
  @spec get_default_model(String.t() | nil) :: String.t() | nil
  def get_default_model(model \\ nil) do
    model ||
      get_app_config(:default_model) ||
      System.get_env("OPENROUTER_DEFAULT_MODEL")
  end

  @doc """
  Gets application name for OpenRouter tracking.
  """
  @spec get_app_name(String.t() | nil) :: String.t() | nil
  def get_app_name(app_name \\ nil) do
    app_name ||
      get_app_config(:app_name) ||
      System.get_env("OPENROUTER_APP_NAME")
  end

  @doc """
  Gets site URL for OpenRouter tracking.
  """
  @spec get_site_url(String.t() | nil) :: String.t() | nil
  def get_site_url(site_url \\ nil) do
    site_url ||
      get_app_config(:site_url) ||
      System.get_env("OPENROUTER_SITE_URL")
  end

  @doc """
  Validates that required configuration is present.
  """
  @spec validate!(keyword()) :: :ok | no_return()
  def validate!(opts \\ []) do
    api_key = get_api_key(opts[:api_key])

    unless api_key do
      raise """
      OpenRouter API key is required.

      You can provide it in one of the following ways:

      1. Pass it directly:
         Openrouter.new(api_key: "or-...")

      2. Set application config:
         config :openrouter, api_key: "or-..."

      3. Set environment variable:
         export OPENROUTER_API_KEY="or-..."
      """
    end

    :ok
  end

  # Private helpers

  defp get_app_config(key) do
    case Application.get_env(:openrouter, key) do
      nil ->
        # Try nested config structure
        config = Application.get_env(:openrouter, :config, %{})
        Map.get(config, key)

      value ->
        value
    end
  end
end
