# stockfish-pool

A small HTTP/JSON service that runs a fixed pool of Stockfish engines for
other applications, built to be safe to put behind a public site:

- **No UCI from callers.** Requests carry a FEN, moves and limits. Each value
  is validated strictly, and every engine command is built by the service.
  Engine options are fixed at startup.
- **Hard ceilings.** Depth, `movetime`, nodes and MultiPV are clamped to
  per-lane maximums. A watchdog sends `stop` when a search overruns and kills
  the engine if it still doesn't answer.
- **Bounded everything.** There is a fixed number of workers and a bounded
  queue per lane. A global engine-seconds budget per minute caps total CPU,
  and an optional per-subject quota (for example, a hashed client IP) caps each
  caller. When any limit is hit, the response is `429` with `Retry-After`.
- **Two lanes.** `interactive` requests always have reserved workers. `batch`
  requests (whole-game analysis) use only the unreserved workers, and only
  while no interactive request is waiting.
- **Self-healing.** A crashed, killed or unresponsive engine is detected and
  restarted with exponential backoff.

This directory is self-contained (its own Gemfile, tests and lint config) so it
can later move to its own repository. `client/` holds the Ruby client gem
(see [client/README.md](client/README.md)); its contract tests run against this
server as part of `rake test`.

## API

All `/v1` endpoints need `Authorization: Bearer <token>` and
`Content-Type: application/json`.

### `POST /v1/analyze`

```json
{
  "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
  "moves": ["e7e5"],
  "lane": "interactive",
  "depth": 16,
  "multipv": 3,
  "movetime_ms": 1000,
  "nodes": 1000000,
  "subject": "9f2c0a1b"
}
```

Only `fen` is required. `moves` are UCI moves played from `fen`. `lane`
defaults to `interactive`. Limits that are omitted use the lane defaults, and
limits that are too high are clamped to the lane's maximum. `subject` is
`[A-Za-z0-9_-]{1,64}` and turns on the per-subject quota.

```json
{
  "bestmove": "g1f3",
  "lines": [
    { "multipv": 1, "move": "g1f3", "score": { "cp": 31 }, "depth": 16, "pv": ["g1f3", "b8c6"] }
  ],
  "engine": "Stockfish 17.1",
  "lane": "interactive",
  "applied": { "depth": 16, "movetime_ms": 1000, "nodes": 1000000, "multipv": 3 },
  "ms": 412
}
```

Scores are from the side to move's point of view, as UCI reports them:
`{ "cp": n }` or `{ "mate": n }`. A position with no legal moves returns
`"bestmove": null` and a single line with `move: null` and a score of
`{ "mate": 0 }` (checkmate) or `{ "cp": 0 }` (stalemate).

| Status | `error` | Meaning |
|---|---|---|
| 400 | `invalid_json` | Body is not JSON |
| 401 | `unauthorized` | Missing or wrong token |
| 413 | `payload_too_large` | Body over 16 KB |
| 415 | `unsupported_media_type` | Content-Type isn't `application/json` |
| 422 | `invalid_request` | Bad FEN, move, lane, limit or subject |
| 429 | `busy` / `quota_exceeded` | Queue full, wait timed out, global budget or subject quota used up. See `Retry-After` |
| 503 | `engine_unavailable` | No worker can serve the lane, or the engine failed mid-search. Safe to retry |

### `GET /healthz`

No token needed. Returns `200` while at least one worker is up, otherwise `503`.

```json
{ "status": "ok", "workers": [{ "id": 1, "reserved": true, "state": "idle", "restarts": 0 }],
  "waiting": { "interactive": 0, "batch": 0 }, "budget": { "used_s": 3.2, "limit_s": 90 } }
```

## Configuration

Everything is set through environment variables. The defaults are sized for a
3 vCPU / 4 GB VPS shared with other services.

| Variable | Default | |
|---|---|---|
| `API_TOKENS` | (none) | Comma-separated, at least 24 characters each. If empty, every `/v1` call is rejected |
| `ENGINE_PATH` | `stockfish` | |
| `POOL_SIZE` / `RESERVED_INTERACTIVE` | `2` / `1` | Reserved is capped at `POOL_SIZE - 1` |
| `THREADS` / `HASH_MB` | `1` / `16` | Per engine. `POOL_SIZE × THREADS` is the real CPU ceiling |
| `GLOBAL_ENGINE_SEC_PER_MIN` | `90` | Engine-seconds per sliding minute, across all callers |
| `SUBJECT_ENGINE_SEC_PER_MIN` / `SUBJECT_BURST_SEC` | `20` / `10` | Per-subject token bucket for the interactive lane |
| `SUBJECT_BATCH_ENGINE_SEC_PER_MIN` / `SUBJECT_BATCH_BURST_SEC` | `60` / `120` | Separate per-subject bucket for the batch lane: one whole-game analysis needs up to about a minute of engine time |
| `INTERACTIVE_DEFAULT_DEPTH` / `_MAX_DEPTH` | `16` / `18` | |
| `INTERACTIVE_MAX_MOVETIME_MS` / `_MAX_NODES` / `_MAX_MULTIPV` | `2000` / `2000000` / `3` | |
| `INTERACTIVE_QUEUE_MAX` / `_QUEUE_WAIT_S` | `8` / `5` | |
| `BATCH_DEFAULT_DEPTH` / `_MAX_DEPTH` | `14` / `14` | |
| `BATCH_MAX_MOVETIME_MS` / `_MAX_NODES` / `_MAX_MULTIPV` | `400` / `1000000` / `3` | |
| `BATCH_QUEUE_MAX` / `_QUEUE_WAIT_S` | `4` / `30` | |
| `STOP_GRACE_MS` / `KILL_GRACE_MS` | `250` / `1000` | After `movetime` + stop grace the watchdog sends `stop`; after kill grace more it kills the engine |
| `HEALTH_INTERVAL_S` | `30` | `isready` ping for idle engines |
| `MAX_MOVES` | `600` | Longest `moves` array accepted |
| `PUMA_THREADS` / `PORT` | `16` / `4000` | Threads must cover the pool plus both queues |

## Development

```bash
cd stockfish-pool
bundle install
bundle exec rake test          # the real-Stockfish tests are skipped unless stockfish is on PATH
API_TOKENS=dev-token-0123456789abcdefgh bundle exec puma -C config/puma.rb
```

Run a single Puma process: the pool lives in that process.

The container image and Quadlet units come in a later change.
