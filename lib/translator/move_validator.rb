# frozen_string_literal: true

module Translator
  # Validates chess piece movements according to standard chess rules
  class MoveValidator
    def initialize(board)
      @board = board
    end

    def valid_move?(from, to, piece)
      case piece.upcase
      when 'N' then valid_knight_move?(from, to)
      when 'B' then valid_bishop_move?(from, to)
      when 'P' then valid_pawn_move?(from, to)
      when 'R' then valid_rook_move?(from, to)
      when 'Q' then valid_queen_move?(from, to)
      when 'K' then valid_king_move?(from, to)
      else false
      end
    end

    def valid_knight_move?(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars

      file_diff = (from_file.ord - to_file.ord).abs
      rank_diff = (from_rank.to_i - to_rank.to_i).abs

      (file_diff == 2 && rank_diff == 1) || (file_diff == 1 && rank_diff == 2)
    end

    def valid_bishop_move?(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars

      file_diff = (from_file.ord - to_file.ord).abs
      rank_diff = (from_rank.to_i - to_rank.to_i).abs

      return false unless file_diff == rank_diff

      path_clear_diagonal?(from, to)
    end

    def valid_rook_move?(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars

      return false unless from_file == to_file || from_rank == to_rank

      if from_file == to_file
        path_clear_vertical?(from, to)
      else
        path_clear_horizontal?(from, to)
      end
    end

    def valid_queen_move?(from, to)
      valid_bishop_move?(from, to) || valid_rook_move?(from, to)
    end

    def valid_king_move?(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars

      file_diff = (from_file.ord - to_file.ord).abs
      rank_diff = (from_rank.to_i - to_rank.to_i).abs

      file_diff <= 1 && rank_diff <= 1
    end

    def valid_pawn_move?(from, to)
      movement = calculate_pawn_movement(from, to)

      if movement[:file_diff].zero?
        valid_forward_pawn_move?(from, to, movement)
      elsif valid_pawn_capture_move?(movement)
        @board[to] || valid_en_passant?(from, to)
      else
        false
      end
    end

    def valid_en_passant?(from, to)
      return false unless valid_last_move_for_en_passant?
      return false unless pawn_on_correct_rank_for_en_passant?(from)
      return false unless moving_to_correct_en_passant_square?(from, to)

      true
    end

    private

    def calculate_pawn_movement(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars
      direction = @board.current_player == :white ? 1 : -1

      {
        file_diff: (from_file.ord - to_file.ord).abs,
        rank_diff: (to_rank.to_i - from_rank.to_i) * direction
      }
    end

    def valid_forward_pawn_move?(from, to, movement)
      case movement[:rank_diff]
      when 1
        !@board[to] # Destination must be empty
      when 2
        direction = @board.current_player == :white ? 1 : -1
        valid_double_step_pawn_move?(from, direction)
      else
        false
      end
    end

    def valid_pawn_capture_move?(movement)
      movement[:file_diff] == 1 && movement[:rank_diff] == 1
    end

    def valid_last_move_for_en_passant?
      return false unless @board.last_move && @board.last_move[:moves].size == 1

      last_from, last_to = @board.last_move[:moves][0].split('-')
      (last_to[1].to_i - last_from[1].to_i).abs == 2
    end

    def pawn_on_correct_rank_for_en_passant?(from)
      correct_rank = @board.current_player == :white ? '5' : '4'
      from[1] == correct_rank
    end

    def moving_to_correct_en_passant_square?(from, to)
      direction = @board.current_player == :white ? 1 : -1
      last_to = @board.last_move[:moves][0].split('-')[1]
      expected_to = "#{last_to[0]}#{from[1].to_i + direction}"
      to == expected_to
    end

    def valid_double_step_pawn_move?(from, direction)
      from_file, from_rank = from.chars
      return false unless (@board.current_player == :white && from_rank == '2') ||
                          (@board.current_player == :black && from_rank == '7')

      middle_square = "#{from_file}#{from_rank.to_i + direction}"
      destination_square = "#{from_file}#{from_rank.to_i + (2 * direction)}"
      !@board[middle_square] && !@board[destination_square]
    end

    def path_clear_diagonal?(from, to)
      from_file, from_rank = from.chars
      to_file, to_rank = to.chars

      file_step = to_file > from_file ? 1 : -1
      rank_step = to_rank.to_i > from_rank.to_i ? 1 : -1

      current_file = from_file.ord + file_step
      current_rank = from_rank.to_i + rank_step

      while current_file.chr != to_file && current_rank.to_s != to_rank
        return false if @board["#{current_file.chr}#{current_rank}"]

        current_file += file_step
        current_rank += rank_step
      end

      true
    end

    def path_clear_vertical?(from, to)
      file = from[0]
      start_rank = [from[1].to_i, to[1].to_i].min + 1
      end_rank = [from[1].to_i, to[1].to_i].max

      (start_rank...end_rank).each do |rank|
        return false if @board["#{file}#{rank}"]
      end
      true
    end

    def path_clear_horizontal?(from, to)
      rank = from[1]
      start_file = [from[0].ord, to[0].ord].min + 1
      end_file = [from[0].ord, to[0].ord].max

      (start_file...end_file).each do |file_ord|
        return false if @board["#{file_ord.chr}#{rank}"]
      end
      true
    end
  end
end
