# frozen_string_literal: true

# Reads optional settings from the environment. Env files (podman --env-file,
# the deploy/env templates) write `KEY=` to mean "not set", which arrives as an
# empty string, so blank values count as unset.
module EnvSetting
  module_function

  # @return [String, nil] the stripped value, or nil when unset or blank
  def get(key, env = ENV)
    value = env[key].to_s.strip
    value.empty? ? nil : value
  end

  # @return [Integer] the value as an integer, or +default+ when unset or blank
  def integer(key, default, env = ENV)
    value = get(key, env)
    value ? Integer(value, 10) : default
  rescue ArgumentError
    raise ArgumentError, "#{key} must be an integer, got #{value.inspect}"
  end
end
