# frozen_string_literal: true

require 'pgn'

# PGNReader reads a PGN string info a PGN::Game object
#
# Usage:
#   reader = PGNReader.new
#   pgn = reader.read(game_str)
class PGNReader
  def initialize
    @line_width = 80 # Standard PGN line width for wrapping
  end

  # Serialize a PGN::Game to PGN format string
  #
  # @param pgn_text [String] the PGN representation
  # @return a [PGN::Game] object comprising the game
  def read(pgn_text)
    return [] if pgn_text.nil? || pgn_text.strip.empty?

    pgn_text = strip_non_ascii(pgn_text)
    pgn_text = ensure_pgn_has_result_termination(pgn_text)
    PGN.parse(pgn_text)
  end

  # Remove non-ASCII characters that the PGN parser cannot handle.
  def strip_non_ascii(pgn_text)
    pgn_text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
            .gsub(/[^\x00-\x7F]/, '')
  end

  # Ensure the PGN text ends with a valid game termination token.
  # If missing, and a [Result "..."] tag exists, append that token to the end.
  def ensure_pgn_has_result_termination(pgn_text)
    return pgn_text if pgn_text.nil? || pgn_text.strip.empty?

    result_tag = pgn_text[/\[Result\s+"([^"]+)"\]/i, 1]
    return pgn_text unless result_tag

    normalized_result = result_tag.strip
    return pgn_text unless ['1-0', '0-1', '1/2-1/2', '*'].include?(normalized_result)

    trimmed = pgn_text.rstrip
    return pgn_text if trimmed.match?(%r{(1-0|0-1|1/2-1/2|\*)\s*\z})

    "#{trimmed} #{normalized_result}\n"
  end
end
