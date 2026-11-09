# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require_relative '../lib/annotation_cache'

class AnnotationCacheTest < Minitest::Test
  def test_builds_once_and_hands_out_independent_copies
    cache = AnnotationCache.new
    builds = 0
    first = cache.fetch_copy(:key) { builds += 1; { moves: ['e4'] } } # rubocop:disable Style/Semicolon
    second = cache.fetch_copy(:key) { flunk 'should be cached' }
    second[:moves] << 'e5'

    assert_equal 1, builds
    assert_equal ['e4'], first[:moves]
    assert_equal ['e4'], cache.fetch_copy(:key) { nil }[:moves]
  end

  def test_least_recently_used_entries_are_dropped
    cache = AnnotationCache.new(max_entries: 2)
    cache.fetch_copy(:a) { 1 }
    cache.fetch_copy(:b) { 2 }
    cache.fetch_copy(:a) { raise 'a should be cached' }
    cache.fetch_copy(:c) { 3 }

    assert_equal 2, cache.size
    assert_equal 1, cache.fetch_copy(:a) { raise 'a was recently used' }
    assert_equal 'rebuilt', cache.fetch_copy(:b) { 'rebuilt' }
  end

  def test_key_changes_when_the_file_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'game.pgn')
      File.write(path, '1. e4 *')
      before = AnnotationCache.key_for(path)
      File.write(path, '1. d4 d5 *')

      refute_equal before, AnnotationCache.key_for(path)
    end
  end
end
