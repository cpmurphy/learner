# frozen_string_literal: true

require 'prop_check'
require_relative 'chess_model'

# A short line of play around one edge case: the move before it, the move
# itself and, where the game goes on, one move after.
# positions[i + 1] is positions[i] after moves[i].
EdgeCaseScenario = Struct.new(:kind, :params, :positions, :moves, :forbidden, keyword_init: true) do
  def inspect
    lines = positions.each_with_index.map do |position, index|
      "  #{position.to_fen}#{"  --#{moves[index]}-->" if moves[index]}"
    end
    lines << "  (#{forbidden} is illegal here)" if forbidden
    "#<#{kind} #{params.inspect}\n#{lines.join("\n")}>"
  end

  alias_method :to_s, :inspect
end

# Builds edge-case scenarios from random boards, and wraps the builders as
# prop_check generators. A builder is deterministic for its arguments
# (including +seed+), so a failing case can be rebuilt from what the failure
# report prints. Every scenario is checked against ChessModel as it is built:
# the positions are well formed and every move is legal.
module EdgeCases
  G = PropCheck::Generators

  class Exhausted < StandardError; end

  COLORS = %w[w b].freeze
  FILES = (0..7).to_a.freeze
  ALL_SQUARES = FILES.product(FILES).freeze
  EXTRA_TYPES = %w[n b r q p].freeze
  ATTACKER_TYPES = %w[q q r r b n p].freeze

  # Every promotion: both colours, every file, every piece, pushing or
  # capturing towards either side.
  PROMOTION_COMBINATIONS = COLORS.product(FILES, ChessModel::PROMOTIONS, [nil, -1, 1]).filter_map do |color, file, piece, capture|
    { color: color, file: file, piece: piece, capture: capture } if capture.nil? || (file + capture).between?(0, 7)
  end.freeze

  module_function

  # --- Builders. White plays the edge-case move; for Black the scenario is mirrored. ---

  def promotion(color:, file:, piece:, capture:, seed:)
    params = { color: color, file: file, piece: piece, capture: capture, seed: seed }
    from = [file, 6]
    to = [file + (capture || 0), 7]
    special = uci(from, to, piece)
    scenario = attempt(seed) do |rng|
      board = { from => 'P' }
      board[to] = %w[q r b n].sample(random: rng) if capture
      place(board, rng, 'K')
      place(board, rng, 'k')
      add_extras(board, rng, rng.rand(0..3))
      next unless legal_in?(board, 'w', special)

      before, prior = unmove(board, 'b', rng)
      next unless before

      after = before.play(prior).play(special)
      line(:promotion, params, before, [prior, special, reply(after, rng, to)])
    end
    oriented(color, scenario)
  end

  def en_passant(color:, file:, from_side:, pinned:, seed:)
    params = { color: color, file: file, from_side: from_side, pinned: pinned, seed: seed }
    capturer = [file + from_side, 4]
    prior = uci([file, 6], [file, 4])
    special = uci(capturer, [file, 5])
    scenario = attempt(seed) do |rng|
      board = { [file, 6] => 'p', capturer => 'P' }
      free = ALL_SQUARES - [[file, 5], [file, 4]]
      free = place_pin(board, rng, file, from_side) & free if pinned
      place(board, rng, 'K', free) unless pinned
      place(board, rng, 'k', free)
      add_extras(board, rng, rng.rand(0..3), free)
      before = position(board, 'b', rng)
      next unless before.well_formed? && before.legal_moves.include?(prior)

      after_push = before.play(prior)
      next unless after_push.legal_moves.include?(special) == !pinned
      next line(:en_passant_pinned, params, before, [prior], forbidden: special) if pinned

      line(:en_passant, params, before, [prior, special, reply(after_push.play(special), rng, [file, 5])])
    end
    oriented(color, scenario)
  end

  # Puts White's king and a black rook or queen on the fifth rank, either side
  # of the two pawns, and returns the squares still free for other pieces
  # (none on that rank, so nothing blocks the pin).
  def place_pin(board, rng, file, from_side)
    king_files, rook_files = pin_files(file, from_side)
    board[[king_files.to_a.sample(random: rng), 4]] = 'K'
    board[[rook_files.to_a.sample(random: rng), 4]] = %w[r q].sample(random: rng)
    ALL_SQUARES.reject { |square| square[1] == 4 }
  end

  def checkmate(color:, seed:)
    terminal(:checkmate, { color: color, seed: seed }, defenders: 0..2, &:checkmate?)
  end

  def stalemate(color:, seed:)
    terminal(:stalemate, { color: color, seed: seed }, defenders: 0..1, defender_types: %w[p], &:stalemate?)
  end

  # Random boards with Black's king on or near an edge and White's pieces close
  # by, kept only when White has a move that ends the game the right way.
  def terminal(kind, params, defenders:, defender_types: EXTRA_TYPES, &finished)
    scenario = attempt(params[:seed], 50_000) do |rng|
      board = {}
      king = rng.rand < 0.75 ? edge_squares.sample(random: rng) : ALL_SQUARES.sample(random: rng)
      board[king] = 'k'
      near = ALL_SQUARES.select { |square| distance(square, king).between?(1, 3) }
      place(board, rng, 'K', near)
      rng.rand(1..3).times { place(board, rng, ATTACKER_TYPES.sample(random: rng).upcase, near) }
      rng.rand(defenders).times { place(board, rng, defender_types.sample(random: rng)) }
      probe = ChessModel::Position.new(board, side: 'w')
      next unless probe.well_formed?

      endings = probe.legal_moves.select { |move| finished.call(probe.play(move)) }
      next if endings.empty?

      before, prior = unmove(board, 'b', rng)
      next unless before

      line(kind, params, before, [prior, endings.sample(random: rng)])
    end
    oriented(params[:color], scenario)
  end

  # --- prop_check generators ---

  def seed
    G.choose(0..((2**31) - 1))
  end

  def element(values)
    G.one_of(*values.map { |value| G.constant(value) })
  end

  def promotion_case
    G.tuple(element(PROMOTION_COMBINATIONS), seed).map { |combination, s| promotion(**combination, seed: s) }
  end

  def en_passant_case
    G.tuple(element(EN_PASSANT_COMBINATIONS), seed).map { |combination, s| en_passant(**combination, seed: s) }
  end

  def checkmate_case
    G.tuple(element(COLORS), seed).map { |color, s| checkmate(color: color, seed: s) }
  end

  def stalemate_case
    G.tuple(element(COLORS), seed).map { |color, s| stalemate(color: color, seed: s) }
  end

  def edge_case
    G.one_of(promotion_case, en_passant_case, checkmate_case, stalemate_case)
  end

  # FENs that pass InputValidator but are often not legal chess: pawns on any
  # rank, kings side by side, random castling rights and en passant squares.
  # Kings and rooks are often on their starting squares, so some castling
  # rights are genuine.
  def well_shaped_fen
    seed.map { |s| random_fen(Random.new(s)) }
  end

  # Any string shaped like a UCI move, legal or not.
  def uci_shaped_move
    square = G.tuple(G.choose(0..7), G.choose(0..7)).map { |file, rank| ChessModel.square_name([file, rank]) }
    G.tuple(square, square, element([nil, nil, nil, *ChessModel::PROMOTIONS])).map(&:join)
  end

  def random_fen(rng)
    board = rng.rand < 0.5 ? home_pieces(rng) : {}
    %w[K k].each { |king| place(board, rng, king) unless board.value?(king) }
    rng.rand(0..14).times { board[ALL_SQUARES.sample(random: rng)] ||= 'pnbrqPNBRQ'[rng.rand(10)] }
    fen = ChessModel::Position.new(board, side: COLORS.sample(random: rng)).to_fen
    fen.sub(' - - 0 1', " #{random_fields(rng)}")
  end

  # Castling rights, en passant square and move counters, all at random.
  def random_fields(rng)
    rights = %w[K Q k q].select { rng.rand < 0.4 }.join
    ep = rng.rand < 0.3 ? "#{'abcdefgh'[rng.rand(8)]}#{%w[3 6].sample(random: rng)}" : '-'
    "#{rights.empty? ? '-' : rights} #{ep} #{rng.rand(0..120)} #{rng.rand(1..200)}"
  end

  # Kings and rooks on their starting squares, now and then with one missing.
  def home_pieces(rng)
    board = { [4, 0] => 'K', [0, 0] => 'R', [7, 0] => 'R', [4, 7] => 'k', [0, 7] => 'r', [7, 7] => 'r' }
    board.delete(board.keys.sample(random: rng)) while rng.rand < 0.3 && board.size > 4
    board
  end

  # --- Helpers ---

  def attempt(seed, tries = 5_000)
    rng = Random.new(seed)
    tries.times do
      scenario = yield rng
      return scenario if scenario
    end
    raise Exhausted, "No scenario after #{tries} tries for seed #{seed}"
  end

  def oriented(color, scenario)
    return scenario if color == 'w'

    moves = scenario.moves.map { |move| ChessModel.flip_move(move) }
    forbidden = scenario.forbidden && ChessModel.flip_move(scenario.forbidden)
    line(scenario.kind, scenario.params, scenario.positions.first.flip, moves, forbidden: forbidden)
  end

  def line(kind, params, start, moves, forbidden: nil)
    moves = moves.compact
    positions = moves.each_with_object([start]) { |move, acc| acc << acc.last.play(move) }
    validate!(positions, moves, forbidden)
    EdgeCaseScenario.new(kind: kind, params: params, positions: positions, moves: moves, forbidden: forbidden)
  end

  def validate!(positions, moves, forbidden)
    positions.each { |position| raise "Badly formed position #{position}" unless position.well_formed? }
    moves.each_with_index do |move, index|
      raise "#{move} is not legal in #{positions[index]}" unless positions[index].legal_moves.include?(move)
    end
    return unless forbidden && positions.last.legal_moves.include?(forbidden)

    raise "#{forbidden} should be illegal in #{positions.last}"
  end

  # The position before a quiet move by +mover+ that leads to +board+, chosen
  # at random among the moves that could have done so: [before, move].
  def unmove(board, mover, rng)
    probe = ChessModel::Position.new(board, side: mover)
    candidates = board.flat_map do |square, piece|
      next [] unless ChessModel.color_of(piece) == mover

      origins_for(probe, square, piece, mover).map { |origin| [origin, square] }
    end
    candidates.shuffle(random: rng).each do |origin, target|
      before_board = board.dup
      before_board[origin] = before_board.delete(target)
      before = position(before_board, mover, rng)
      move = uci(origin, target)
      return [before, move] if before.well_formed? && before.legal_moves.include?(move)
    end
    nil
  end

  def origins_for(probe, square, piece, mover)
    if piece.downcase == 'p'
      origin = ChessModel.add(square, [0, mover == 'w' ? -1 : 1])
      return [] unless origin[1].between?(1, 6) && !probe.board.key?(origin)

      [origin]
    else
      probe.attacks_from(square).reject { |origin| probe.board.key?(origin) }
    end
  end

  # A position with random move counters. Now and then the halfmove clock is
  # close to the fifty-move limit.
  def position(board, side, rng)
    halfmove = rng.rand < 0.15 ? rng.rand(95..99) : rng.rand(0..30)
    ChessModel::Position.new(board, side: side, halfmove: halfmove, fullmove: rng.rand(1..150))
  end

  def legal_in?(board, side, move)
    probe = ChessModel::Position.new(board, side: side)
    probe.well_formed? && probe.legal_moves.include?(move)
  end

  # A random legal reply, often one that lands on +focus+ (such as recapturing
  # a promoted piece). nil when there is none (checkmate or stalemate).
  def reply(position, rng, focus)
    moves = position.legal_moves
    return nil if moves.empty?

    focused = moves.select { |move| move[2, 2] == ChessModel.square_name(focus) }
    (focused.any? && rng.rand < 0.5 ? focused : moves).sample(random: rng)
  end

  def place(board, rng, piece, squares = ALL_SQUARES)
    free = squares.reject { |square| board.key?(square) }
    free = free.reject { |square| [0, 7].include?(square[1]) } if piece.downcase == 'p'
    board[free.sample(random: rng)] = piece unless free.empty?
  end

  def add_extras(board, rng, count, squares = ALL_SQUARES)
    count.times do
      type = EXTRA_TYPES.sample(random: rng)
      place(board, rng, rng.rand < 0.5 ? type.upcase : type, squares)
    end
  end

  # Files for the king and the rook in a pinned en passant: the king is on the
  # capturing pawn's side, the rook on the far side of the captured pawn.
  def pin_files(file, from_side)
    capturer = file + from_side
    king_files, rook_files = from_side.negative? ? [0...capturer, (file + 1)..7] : [(capturer + 1)..7, 0...file]
    [king_files, rook_files] unless king_files.none? || rook_files.none?
  end

  def edge_squares
    ALL_SQUARES.select { |file, rank| [0, 7].include?(file) || [0, 7].include?(rank) }
  end

  def distance(one, other)
    [(one[0] - other[0]).abs, (one[1] - other[1]).abs].max
  end

  def uci(from, to, promotion = nil)
    "#{ChessModel.square_name(from)}#{ChessModel.square_name(to)}#{promotion}"
  end

  # Every en passant capture: both colours, every file of the captured pawn,
  # from either side. With +pinned+, the capture would leave the king in check
  # along the rank (the captured pawn and the capturing pawn both leave it), so
  # it is illegal; only combinations with room for the king and the rook have it.
  EN_PASSANT_COMBINATIONS = COLORS.product(FILES, [-1, 1], [false, true]).filter_map do |color, file, from_side, pinned|
    combination = { color: color, file: file, from_side: from_side, pinned: pinned }
    combination if (file + from_side).between?(0, 7) && (!pinned || pin_files(file, from_side))
  end.freeze
end
