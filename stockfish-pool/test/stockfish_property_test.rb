# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'support/edge_case_generators'
require_relative 'support/engine_server'

# Property tests of POST /v1/analyze against real Stockfish, over HTTP, using
# generated positions around promotions (every file, every piece), en passant
# captures (every file, plus captures a pin makes illegal), checkmates and
# stalemates. Each scenario covers the move before the edge case, the move
# itself and, where the game goes on, one move after.
#
# The properties:
# - A position gives the same analysis however it is sent: as a FEN, or as an
#   earlier FEN plus the moves that lead to it. This catches moves the engine
#   silently ignores, and FEN fields (en passant, clocks) it reads differently.
# - Every answer is sound by ChessModel: the best move and each PV are legal,
#   MultiPV lines are distinct, mates in one are found, and a position with no
#   legal moves is reported as checkmate or stalemate.
# - Concurrent requests get the same answers as the same requests sent one at
#   a time, so workers do not leak state or answers to each other.
#
# Skipped unless Stockfish is installed. PROP_RUNS (default 25) sets the runs
# per property; PROP_DEPTH (default 8) the search depth.
class StockfishPropertyTest < Minitest::Test
  G = PropCheck::Generators
  RUNS = Integer(ENV.fetch('PROP_RUNS', '25'))
  DEPTH = Integer(ENV.fetch('PROP_DEPTH', '8'))
  LANES = %w[interactive batch].freeze

  def setup
    skip 'Stockfish not installed' unless EngineServer::ENGINE
    @server = EngineServer.shared
  end

  def test_promotions
    check_scenarios(EdgeCases.promotion_case)
  end

  def test_en_passant
    check_scenarios(EdgeCases.en_passant_case)
  end

  def test_checkmates
    check_scenarios(EdgeCases.checkmate_case)
  end

  def test_stalemates
    check_scenarios(EdgeCases.stalemate_case)
  end

  # Random sampling may miss a file or a piece, so this goes through every
  # promotion and en passant combination once, each on a fresh random board.
  def test_every_promotion_and_en_passant_combination
    rng = Random.new
    scenarios = EdgeCases::PROMOTION_COMBINATIONS.map { |c| EdgeCases.promotion(**c, seed: rng.rand(2**31)) } +
                EdgeCases::EN_PASSANT_COMBINATIONS.map { |c| EdgeCases.en_passant(**c, seed: rng.rand(2**31)) }

    scenarios.each { |scenario| assert_scenario(scenario, multipv: rng.rand(1..3), lane: LANES.sample(random: rng)) }
    assert_engines_healthy
  end

  def test_concurrent_requests_match_sequential_results
    batch = G.array(G.tuple(EdgeCases.edge_case, G.choose(1..3), EdgeCases.element(LANES)), min: 3, max: 8)
    forall(batch, runs: [RUNS / 5, 2].max) do |cases|
      requests = cases.flat_map { |scenario, multipv, lane| requests_for(scenario, multipv, lane).map(&:last) }
      requests += [{ fen: 'not a fen' }, { fen: TestSupport::START_FEN, moves: ['e2e9'] }]
      order = requests.each_index.to_a.shuffle
      sequential = order.to_h { |index| [index, @server.analyze(requests[index])] }
      concurrent = order.zip(@server.analyze_concurrently(order.map { |index| requests[index] })).to_h

      requests.each_index do |index|
        alone = sequential[index]
        together = concurrent[index]
        message = "#{requests[index]}\nalone: #{alone.body}\ntogether: #{together.body}"

        assert_equal alone.status, together.status, message
        assert_equal(alone.analysis, together.analysis, message) if alone.status == 200
      end
    end

    assert_engines_healthy
  end

  # Input that is shaped right but is not legal chess is refused with a 422
  # before it reaches an engine, so no engine ever crashes on it.
  def test_well_shaped_input_never_crashes_an_engine
    forall(EdgeCases.well_shaped_fen, G.array(EdgeCases.uci_shaped_move, max: 3), runs: RUNS * 4) do |fen, moves|
      response = @server.analyze(fen: fen, moves: moves, depth: 4)

      assert_includes [200, 422], response.status, "#{fen} #{moves} -> #{response.body}"
    end
    assert_engines_healthy
  end

  # A move is accepted exactly when it is legal, so Stockfish never skips one.
  def test_moves_are_accepted_only_when_legal
    cases = G.tuple(EdgeCases.edge_case, G.choose(0..3), G.boolean, EdgeCases.uci_shaped_move)
    forall(cases) do |scenario, index, pick_legal, random_move|
      position = scenario.positions[index % scenario.positions.size]
      move = pick_legal && position.legal_moves.any? ? position.legal_moves.min : random_move
      response = @server.analyze(fen: position.to_fen, moves: [move], depth: 4)

      assert_equal position.legal_moves.include?(move) ? 200 : 422, response.status,
                   "#{position} #{move} -> #{response.body}"
    end
  end

  private

  def check_scenarios(scenario_generator)
    forall(scenario_generator, G.choose(1..3), EdgeCases.element(LANES)) do |scenario, multipv, lane|
      assert_scenario(scenario, multipv: multipv, lane: lane)
    end
    assert_engines_healthy
  end

  def forall(*generators, runs: RUNS, &block)
    PropCheck::Property.new(*generators).with_config(n_runs: runs, max_shrink_steps: 40).check(&block)
  end

  # Every position of the scenario, sent as its own FEN and as each earlier
  # FEN plus the moves from there: [index of the position, request params].
  def requests_for(scenario, multipv, lane)
    scenario.positions.each_index.flat_map do |target|
      (0..target).map do |start|
        [target, { fen: scenario.positions[start].to_fen, moves: scenario.moves[start...target],
                   depth: DEPTH, multipv: multipv, lane: lane }]
      end
    end
  end

  def assert_scenario(scenario, multipv:, lane:)
    requests = requests_for(scenario, multipv, lane)
    responses = @server.analyze_concurrently(requests.map(&:last))
    requests.zip(responses).group_by { |(target, _), _| target }.each do |target, pairs|
      pairs.each do |(_, params), response|
        assert_equal 200, response.status, "#{scenario.inspect}\n#{params} -> #{response.body}"
      end
      analyses = pairs.map { |_, response| response.analysis }.uniq

      assert_equal 1, analyses.size, "Position #{target} analysed differently depending on how it was sent:\n" \
                                     "#{scenario.inspect}\n#{pairs.map { |(_, p), r| "#{p}\n  -> #{r.body}" }.join("\n")}"
      assert_sound(scenario.positions[target], analyses.first, multipv, scenario)
    end
  end

  def assert_sound(position, analysis, multipv, scenario)
    context = "#{position}\n#{analysis}\nin #{scenario.inspect}"
    lines = analysis['lines']

    lines.each { |line| assert_score_shape(line['score'], context) }
    if position.legal_moves.empty?
      assert_no_moves(position, analysis, context)
    else
      assert_includes position.legal_moves, analysis['bestmove'], context
      assert_equal [multipv, position.legal_moves.size].min, lines.size, context
      assert_equal analysis['bestmove'], lines.first['move'], context
      assert_equal lines.size, lines.map { |line| line['move'] }.uniq.size, "Repeated MultiPV move: #{context}"
      lines.each { |line| assert_legal_line(position, line, context) }
      assert_finds_mate_in_one(position, analysis, context)
      refute_equal scenario.forbidden, analysis['bestmove'], context if scenario.forbidden
    end
  end

  def assert_no_moves(position, analysis, context)
    assert_nil analysis['bestmove'], context
    expected = position.checkmate? ? { 'mate' => 0 } : { 'cp' => 0 }

    assert_equal [{ 'multipv' => 1, 'move' => nil, 'score' => expected }],
                 analysis['lines'].map { |line| line.slice('multipv', 'move', 'score') }, context
  end

  def assert_score_shape(score, context)
    assert_equal 1, score.size, context
    assert_includes %w[cp mate], score.keys.first, context
    assert_kind_of Integer, score.values.first, context
  end

  def assert_legal_line(position, line, context)
    assert_equal line['pv'].first, line['move'], context
    line['pv'].reduce(position) do |current, move|
      assert_includes current.legal_moves, move, "Illegal PV move #{move} in #{current}: #{context}"
      current.play(move)
    end
  end

  def assert_finds_mate_in_one(position, analysis, context)
    return unless position.legal_moves.any? { |move| position.play(move).checkmate? }

    assert_equal({ 'mate' => 1 }, analysis['lines'].first['score'], "Missed mate in one: #{context}")
    assert_predicate position.play(analysis['bestmove']), :checkmate?, context
  end

  def assert_engines_healthy
    health = @server.health

    assert_equal 'ok', health['status'], health.to_s
    assert(health['workers'].all? { |worker| worker['restarts'].zero? }, "An engine was restarted: #{health}")
  end
end
