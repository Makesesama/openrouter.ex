# Exclude integration tests by default
# Run integration tests with: mix test --only integration
ExUnit.start(exclude: [:integration])

# Configure test mode for reqord if available
if Code.ensure_loaded?(Reqord) do
  Reqord.configure(mode: System.get_env("REQORD_MODE", "replay"))
end
