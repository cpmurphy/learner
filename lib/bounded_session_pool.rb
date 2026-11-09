# frozen_string_literal: true

require 'rack/session/pool'

# An in-memory session store with a size limit and idle expiry.
#
# Rack::Session::Pool keeps every session forever, and also stores an empty one
# for every request that presents an unknown session cookie (forged, or from
# before a restart), so on a public site its memory grows without bound. This
# store:
# - never keeps a session until it holds data (made-up cookies cost nothing);
# - drops sessions idle for longer than +idle_ttl+ seconds;
# - evicts the least recently used sessions beyond +max_sessions+.
class BoundedSessionPool < Rack::Session::Pool
  DEFAULT_MAX_SESSIONS = 500
  DEFAULT_IDLE_TTL = 2 * 60 * 60

  def initialize(app, options = {})
    options = options.dup
    @max_sessions = options.delete(:max_sessions) || DEFAULT_MAX_SESSIONS
    @idle_ttl = options.delete(:idle_ttl) || DEFAULT_IDLE_TTL
    @clock = options.delete(:clock) || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    super
    @last_seen = {} # private_id => time, least recently used first
  end

  def find_session(_req, sid)
    @mutex.synchronize do
      expire_idle
      session = sid && get_session_with_fallback(sid)
      return [generate_sid(use_mutex: false), {}] unless session

      touch(sid.private_id)
      [sid, session]
    end
  end

  def write_session(_req, session_id, new_session, _options)
    @mutex.synchronize do
      key = session_id.private_id
      return session_id if new_session.empty? && !@pool.key?(key)

      @pool.store(key, new_session)
      touch(key)
      evict_overflow
      session_id
    end
  end

  # Unlike Pool, does not store an empty replacement session (which would
  # escape the size limit); the new id is stored once it holds data.
  def delete_session(_req, session_id, options)
    @mutex.synchronize do
      forget(session_id.public_id)
      forget(session_id.private_id)
      generate_sid(use_mutex: false) unless options[:drop]
    end
  end

  def size
    @mutex.synchronize { @pool.size }
  end

  private

  # Called with @mutex held. Re-inserting moves the key to the end (most recent).
  def touch(key)
    @last_seen.delete(key)
    @last_seen[key] = @clock.call
  end

  # Called with @mutex held.
  def expire_idle
    cutoff = @clock.call - @idle_ttl
    while (oldest = @last_seen.first) && oldest[1] < cutoff
      forget(oldest[0])
    end
  end

  # Called with @mutex held.
  def evict_overflow
    forget(@last_seen.first[0]) while @pool.size > @max_sessions && @last_seen.any?
  end

  def forget(key)
    @last_seen.delete(key)
    @pool.delete(key)
  end
end
