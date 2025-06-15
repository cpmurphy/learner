# frozen_string_literal: true

# This is a Rack configuration file.
# It's used by servers like Puma or Rackup to start the application.

require './app' # Load our Sinatra application from app.rb

run Sinatra::Application
