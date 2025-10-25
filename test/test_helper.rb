# frozen_string_literal: true

# Set test environment before loading anything else
ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/test/'
end

require 'minitest/autorun'
require 'minitest/mock'
