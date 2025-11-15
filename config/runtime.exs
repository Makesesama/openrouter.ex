import Config

# Runtime configuration for OpenRouter API key
if config_env() == :test do
  config :openrouter,
    config: %{
      api_key: System.get_env("OPENROUTER_API_KEY")
    }
end
