# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require_relative '../app'

# Pages and their assets must be revalidated, so phones pick up a deploy at once.
class AppCacheControlTest < Minitest::Test
  include Rack::Test::Methods

  def app
    LearnerApp
  end

  %w[/ /game /login.html /styles/style.css /scripts/main.js].each do |path|
    define_method("test_#{path.tr('/.', '__')}_must_be_revalidated") do
      get path

      assert_equal 200, last_response.status
      assert_equal 'no-cache', last_response.headers['Cache-Control']
      refute_nil last_response.headers['Last-Modified']
    end
  end

  def test_unchanged_stylesheet_is_not_modified
    get '/styles/style.css'
    get '/styles/style.css', {}, 'HTTP_IF_MODIFIED_SINCE' => last_response.headers['Last-Modified']

    assert_equal 304, last_response.status
  end
end
