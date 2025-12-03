# frozen_string_literal: true

require 'pgn'

# PGNWriter serializes a PGN::Game object to PGN string format
#
# Usage:
#   writer = PGNWriter.new
#   pgn_string = writer.write(game)
#
# The writer handles:
# - Tags (Event, Site, Date, White, Black, Result, etc.)
# - Moves with full move numbers
# - Annotations (NAGs like $201, $2, etc.)
# - Comments in curly braces
# - Variations in parentheses
# - Result termination
class PGNWriter
  def initialize
    @line_width = 80 # Standard PGN line width for wrapping
  end

  # Serialize a PGN::Game to PGN format string
  #
  # @param game [PGN::Game] the game to serialize
  # @return [String] the PGN representation
  def write(game)
    output = []
    output << write_tags(game)
    output << '' # Empty line between tags and moves
    output << write_moves(game)
    output.join("\n")
  end

  private

  # Write all tag pairs in [Key "Value"] format
  def write_tags(game)
    return '' unless game.tags

    # Standard tag order (Seven Tag Roster)
    standard_tags = %w[Event Site Date Round White Black Result]

    tags_output = []

    # Write standard tags first, in order
    standard_tags.each do |tag|
      tags_output << format_tag(tag, game.tags[tag]) if game.tags[tag]
    end

    # Write remaining tags in alphabetical order
    remaining_tags = game.tags.keys.sort - standard_tags
    remaining_tags.each do |tag|
      tags_output << format_tag(tag, game.tags[tag])
    end

    tags_output.join("\n")
  end

  # Format a single tag
  def format_tag(key, value)
    "[#{key} \"#{escape_string(value)}\"]"
  end

  # Escape special characters in tag values
  def escape_string(str)
    return '' if str.nil?

    str.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
  end

  # Write all moves with annotations, comments, and variations
  def write_moves(game)
    return game.result.to_s if game.moves.empty?

    moves_text = ''
    move_number = 1

    game.moves.each_with_index do |move, index|
      is_white = index.even?
      prefix = format_move_number_prefix(is_white, index.zero?, move_number, moves_text)
      moves_text += prefix
      moves_text += format_move_with_annotations(move, move_number, is_white)
      move_number += 1 unless is_white
    end

    moves_text += " #{game.result}" if game.result
    wrap_moves_text(moves_text.strip)
  end

  # Write a variation (recursive for nested variations)
  #
  # @param variation [Array<PGN::MoveText>] the variation moves
  # @param start_move_number [Integer] the move number where variation starts
  # @param starts_with_black [Boolean] whether variation starts with black's move
  # @return [String] formatted variation string
  def write_variation(variation, start_move_number, starts_with_black)
    return '()' if variation.empty?

    var_text = ''
    move_number = start_move_number

    variation.each_with_index do |move, index|
      is_white = starts_with_black ? index.odd? : index.even?
      prefix = format_move_number_prefix(is_white, index.zero?, move_number, var_text)
      var_text += prefix
      var_text += format_move_with_annotations(move, move_number, is_white)
      move_number += 1 unless is_white
    end

    "(#{var_text})"
  end

  # Format the move number prefix (e.g., "1.", "1...", or " ")
  #
  # @param is_white [Boolean] whether this is white's move
  # @param is_first [Boolean] whether this is the first move
  # @param move_number [Integer] the current move number
  # @param existing_text [String] existing text to check if we need a space
  # @return [String] the formatted prefix
  def format_move_number_prefix(is_white, is_first, move_number, existing_text)
    if is_white
      prefix = existing_text.empty? ? '' : ' '
      "#{prefix}#{move_number}."
    elsif is_first
      "#{move_number}..."
    else
      ' '
    end
  end

  # Format a move with its annotations, comments, and variations
  #
  # @param move [PGN::MoveText] the move to format
  # @param move_number [Integer] the current move number
  # @param is_white [Boolean] whether this is white's move
  # @return [String] the formatted move string
  def format_move_with_annotations(move, move_number, is_white)
    text = move.notation.to_s
    text += format_annotations(move.annotation) if move.annotation && !move.annotation.empty?
    text += " {#{move.comment}}" if move.comment && !move.comment.empty?
    text += format_variations(move.variations, move_number, is_white) if move.variations && !move.variations.empty?
    text
  end

  # Format annotations (NAGs) for a move
  #
  # @param annotations [Array] array of annotation strings
  # @return [String] formatted annotations
  def format_annotations(annotations)
    annotations.map { |nag| " #{nag}" }.join
  end

  # Format variations for a move
  #
  # @param variations [Array] array of variation arrays
  # @param move_number [Integer] the current move number
  # @param is_white [Boolean] whether current move is white's
  # @return [String] formatted variations
  def format_variations(variations, move_number, is_white)
    variations.map { |variation| " #{write_variation(variation, move_number, !is_white)}" }.join
  end

  # Wrap moves text to standard line width
  # PGN standard is to wrap at 80 characters
  def wrap_moves_text(text)
    return text if text.length <= @line_width

    lines = []
    current_line = ''

    text.split.each do |word|
      if current_line.empty?
        current_line = word
      elsif (current_line.length + 1 + word.length) <= @line_width
        current_line += " #{word}"
      else
        lines << current_line
        current_line = word
      end
    end

    lines << current_line unless current_line.empty?
    lines.join("\n")
  end
end
