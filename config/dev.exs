import Config

# Development configuration
config :openrouter,
  config: %{
    api_key: System.get_env("OPENROUTER_API_KEY")
  }
