# stockfish_pool_client

Ruby client for the [stockfish-pool](../README.md) service. It uses only the
standard library (`net/http`, `json`) and is thread-safe: each call opens its
own connection.

```ruby
# Gemfile
gem 'stockfish_pool_client', path: 'stockfish-pool/client'
```

```ruby
require 'stockfish_pool_client'

client = StockfishPool::Client.new(url: ENV.fetch('ENGINE_URL'), token: ENV.fetch('ENGINE_TOKEN'))
result = client.analyze(fen: fen, moves: ['e2e4'], multipv: 3, lane: :interactive, subject: hashed_ip)

result.bestmove                 # => "e7e5" (nil when there are no legal moves)
result.lines.first.score.cp     # => -23, from the side to move's point of view
result.lines.first.score.mate?  # => false
result.applied                  # => { depth: 16, movetime_ms: 2000, nodes: 2000000, multipv: 3 }
```

| Error | When | Retry? |
|---|---|---|
| `Unauthorized` | Token missing or wrong | No: fix the configuration |
| `InvalidRequest` | Bad FEN, move, lane, limit or subject | No |
| `Busy` | Queue full, wait timed out, or global budget used up | After `retry_after` seconds |
| `QuotaExceeded` | The subject's engine time is used up | After `retry_after` seconds |
| `Unavailable` | Service unreachable, or no healthy engine | The client retries once (`retries:`); then it's up to you |
| `ProtocolError` | Unexpected response | No |

`Busy`, `QuotaExceeded` and `Unavailable` all inherit from `RetryableError`,
and every error inherits from `StockfishPool::Client::Error`. Read timeouts and
dropped connections are never retried, because the search may still be using
an engine.

Options: `open_timeout:` (2 s), `read_timeout:` (40 s, enough for the batch
lane's queue wait), `retries:` (1), `retry_delay:` (0.5 s).
