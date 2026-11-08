# frozen_string_literal: true

# A scriptable stand-in for Stockfish used by the tests.
#
# Usage: ruby fake_engine.rb MODE [LOG_PATH]
#   normal       answers searches immediately
#   ignore_stop  never sends bestmove, even after "stop"
#   needs_stop   sends bestmove only after "stop"
#   crash_on_go  exits as soon as a search starts
#   no_uciok     never completes the handshake
#
# Every command received is appended to LOG_PATH when given.

$stdout.sync = true
mode = ARGV.fetch(0, 'normal')
# The log stays open for the life of this short-lived process.
log = ARGV[1] && File.open(ARGV[1], 'a').tap { |file| file.sync = true } # rubocop:disable Style/FileOpen
multipv = 1
searching = false

def emit_result(multipv)
  (1..multipv).each do |n|
    puts "info depth 12 seldepth 14 multipv #{n} score cp #{40 - (n * 10)} nodes 1000 nps 1 time 5 pv e2e4 e7e5 g1f3"
  end
  puts 'bestmove e2e4 ponder e7e5'
end

$stdin.each_line do |raw|
  line = raw.chomp
  log&.puts(line)
  case line
  when 'uci'
    next if mode == 'no_uciok'

    puts 'id name FakeFish 1.0'
    puts 'uciok'
  when 'isready' then puts 'readyok'
  when /\Asetoption name MultiPV value (\d+)\z/ then multipv = Regexp.last_match(1).to_i
  when /\Ago /
    exit 1 if mode == 'crash_on_go'
    searching = true
    next unless mode == 'normal'

    emit_result(multipv)
    searching = false
  when 'stop'
    next unless searching && mode == 'needs_stop'

    emit_result(multipv)
    searching = false
  when 'quit' then break
  end
end
