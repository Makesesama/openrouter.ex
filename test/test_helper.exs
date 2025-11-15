# Start reqord application for HTTP recording/replay
{:ok, _} = Application.ensure_all_started(:reqord)

# Exclude integration tests by default
# Run integration tests with: mix test --only integration
# Also exclude :skip_reqord tests that don't work with cassette replay
ExUnit.start(exclude: [:integration, :skip_reqord])

# Reqord will automatically handle HTTP recording/replay
# Use environment variable to control mode:
#   REQORD=none (default) - Replay from cassettes
#   REQORD=new_episodes - Record new requests, replay existing
#   REQORD=all - Re-record everything
