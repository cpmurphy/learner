# frozen_string_literal: true

# Remembers the result of whole-game analysis for library files, so loading an
# unannotated file runs Stockfish once rather than for every visitor.
#
# Entries are keyed by path, size and modification time, so editing a file
# invalidates its entry. Games are stored serialised and every caller gets its
# own copy, because sessions modify their games (variations, annotations).
class AnnotationCache
  DEFAULT_MAX_ENTRIES = 50

  def initialize(max_entries: DEFAULT_MAX_ENTRIES)
    @max_entries = max_entries
    @entries = {} # key => Marshal dump, least recently used first
    @mutex = Mutex.new
  end

  def self.key_for(path)
    stat = File.stat(path)
    [File.expand_path(path), stat.size, stat.mtime.to_r]
  end

  # Returns a copy of the cached value for +key+, or yields to build it, caches
  # the result and returns a copy. Concurrent misses may both build; the
  # result is the same either way.
  def fetch_copy(key)
    dump = lookup(key)
    return Marshal.load(dump) if dump # rubocop:disable Security/MarshalLoad -- data this process wrote

    dump = Marshal.dump(yield)
    insert(key, dump)
    Marshal.load(dump) # rubocop:disable Security/MarshalLoad -- data this process wrote
  end

  def size
    @mutex.synchronize { @entries.size }
  end

  private

  def lookup(key)
    @mutex.synchronize do
      dump = @entries.delete(key)
      @entries[key] = dump if dump
      dump
    end
  end

  def insert(key, dump)
    @mutex.synchronize do
      @entries.delete(key)
      @entries[key] = dump
      @entries.delete(@entries.first[0]) while @entries.size > @max_entries
    end
  end
end
