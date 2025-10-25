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
      # Determine if this is white's or black's move
      is_white = index.even?

      # Add move number for white, or for black if starting mid-game
      if is_white
        moves_text += ' ' unless moves_text.empty?
        moves_text += "#{move_number}."
      elsif index == 0
        # If starting with black's move, use ellipsis
        moves_text += "#{move_number}..."
      else
        # Black's move after white's move - add space
        moves_text += ' '
      end

      # Add the move notation
      moves_text += move.notation.to_s

      # Add annotations (NAGs like $201, $2, etc.)
      if move.annotation && !move.annotation.empty?
        move.annotation.each do |nag|
          moves_text += " #{nag}"
        end
      end

      # Add comment if present
      if move.comment && !move.comment.empty?
        moves_text += " {#{move.comment}}"
      end

      # Add variations if present
      if move.variations && !move.variations.empty?
        move.variations.each do |variation|
          moves_text += " #{write_variation(variation, move_number, !is_white)}"
        end
      end

      # Increment move number after black's move
      move_number += 1 unless is_white
    end

    # Add result
    moves_text += " #{game.result}" if game.result

    # Wrap text
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

      # Add move number
      if is_white
        var_text += ' ' unless var_text.empty?
        var_text += "#{move_number}."
      elsif index == 0
        var_text += "#{move_number}..."
      else
        # Black's move after white's move - add space
        var_text += ' '
      end

      # Add move
      var_text += move.notation.to_s

      # Add annotations
      if move.annotation && !move.annotation.empty?
        move.annotation.each do |nag|
          var_text += " #{nag}"
        end
      end

      # Add comment
      if move.comment && !move.comment.empty?
        var_text += " {#{move.comment}}"
      end

      # Add nested variations
      if move.variations && !move.variations.empty?
        move.variations.each do |nested_var|
          var_text += " #{write_variation(nested_var, move_number, !is_white)}"
        end
      end

      move_number += 1 unless is_white
    end

    "(#{var_text})"
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
