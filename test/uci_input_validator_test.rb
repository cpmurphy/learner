# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/uci_input_validator'

class UciInputValidatorTest < Minitest::Test
  START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

  def test_accepts_valid_fens
    [
      START_FEN,
      'r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq d3 0 3',
      '6r1/1pk2p2/p1p1p2p/P2r2pP/4KP2/R2P4/1P6/7R w - g6 0 25',
      '8/8/1k6/3K4/5R2/8/2B5/8 w - - 0 1',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3KBNR w Kq - 0 1'
    ].each { |fen| assert UciInputValidator.valid_fen?(fen), "expected valid: #{fen}" }
  end

  def test_rejects_line_break_injection
    refute UciInputValidator.valid_fen?("#{START_FEN}\nsetoption name Threads value 1024")
    refute UciInputValidator.valid_fen?("#{START_FEN}\r\nquit")
    refute UciInputValidator.valid_uci_move?("e2e4\nsetoption name Hash value 4096")
  end

  def test_rejects_malformed_fens
    [
      nil,
      42,
      '',
      'mock_fen',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 extra',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1',
      'rnbqkbnr/ppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      'rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      'rnbqqbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w  - 0 1',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w QK - 0 1',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e4 0 1',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1',
      "#{START_FEN} #{'1' * 100}"
    ].each { |fen| refute UciInputValidator.valid_fen?(fen), fen.inspect }
  end

  def test_uci_moves
    %w[e2e4 g1f3 e7e8q a7a8n].each { |move| assert UciInputValidator.valid_uci_move?(move), "expected valid: #{move}" }
    [nil, '', 'e4', 'Nf3', 'e2e9', 'i2i4', 'e7e8k', 'e2e4 ', 'O-O'].each do |move|
      refute UciInputValidator.valid_uci_move?(move), move.inspect
    end
  end

  def test_bang_methods_raise
    assert_raises(UciInputValidator::InvalidInputError) { UciInputValidator.validate_fen!('bad') }
    assert_raises(UciInputValidator::InvalidInputError) { UciInputValidator.validate_uci_move!('bad') }
    assert_equal START_FEN, UciInputValidator.validate_fen!(START_FEN)
  end
end
