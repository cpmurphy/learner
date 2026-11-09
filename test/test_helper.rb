# frozen_string_literal: true

# Set test environment before loading anything else
ENV['RACK_ENV'] = 'test'
# Rate limits are global; the suite makes many requests from one address. Tests
# that exercise the limits turn them back on explicitly.
ENV['RATE_LIMITS'] ||= 'off'

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/test/'
end

require 'minitest/autorun'
require 'minitest/mock'
