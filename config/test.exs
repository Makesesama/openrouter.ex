import Config

# Configure OpenRouter to use Req.Test plug for reqord integration
config :openrouter,
  req_options: [plug: {Req.Test, Openrouter.ReqStub}]

# Reqord configuration for HTTP recording/replay in tests
config :reqord,
  default_mode: :none,
  cassette_dir: "test/support/cassettes",
  match_on: [:method, :uri, :body]
