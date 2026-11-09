# frozen_string_literal: true

# A non-blocking limit on how many whole-game analyses run at once.
#
# A whole-game analysis holds a web server thread for as long as the engine
# takes, and Puma has only a few threads; without a limit, a handful of
# visitors pasting games at once would leave none for anyone else. A request
# that finds every slot taken is refused at once rather than queued.
class AnalysisSlots
  def initialize(limit)
    raise ArgumentError, 'limit must be positive' unless limit.positive?

    @limit = limit
    @in_use = 0
    @mutex = Mutex.new
  end

  # Runs the block in a slot and returns [true, result], or returns [false, nil]
  # without running it when every slot is taken.
  def run
    return [false, nil] unless acquire

    begin
      [true, yield]
    ensure
      release
    end
  end

  def in_use
    @mutex.synchronize { @in_use }
  end

  private

  def acquire
    @mutex.synchronize do
      return false if @in_use >= @limit

      @in_use += 1
      true
    end
  end

  def release
    @mutex.synchronize { @in_use -= 1 }
  end
end
