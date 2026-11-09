# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'rack/utils'

# Hashes and verifies the owner's password with scrypt (from Ruby's OpenSSL,
# so no native gem is needed). The encoded form, stored in OWNER_PASSWORD_HASH, is
#
#   scrypt$<N>$<r>$<p>$<salt, base64>$<hash, base64>
#
# Generate one with `bin/owner-password`.
module OwnerPassword
  N = 2**14 # 16 MiB of memory per hash with r = 8
  R = 8
  P = 1
  KEY_LENGTH = 32
  SALT_LENGTH = 16

  module_function

  # +cost+, +block_size+ and +parallelization+ are scrypt's N, r and p.
  def create(password, cost: N, block_size: R, parallelization: P)
    salt = OpenSSL::Random.random_bytes(SALT_LENGTH)
    digest = derive(password, salt, cost, block_size, parallelization)
    ['scrypt', cost, block_size, parallelization, Base64.strict_encode64(salt),
     Base64.strict_encode64(digest)].join('$')
  end

  # @return [Boolean] false for a wrong password or a malformed +encoded+ value
  def verify(password, encoded)
    scheme, n, r, p, salt, digest = encoded.to_s.split('$')
    return false unless scheme == 'scrypt' && [n, r, p, salt, digest].none?(&:nil?)

    expected = Base64.strict_decode64(digest)
    actual = derive(password.to_s, Base64.strict_decode64(salt), Integer(n), Integer(r), Integer(p))
    Rack::Utils.secure_compare(actual, expected)
  rescue ArgumentError, OpenSSL::KDF::KDFError
    false
  end

  # Raises ArgumentError unless +encoded+ looks like a value #create produced.
  def validate!(encoded)
    scheme, *params = encoded.to_s.split('$')
    raise ArgumentError, 'OWNER_PASSWORD_HASH must be generated with bin/owner-password' unless
      scheme == 'scrypt' && params.size == 5

    encoded
  end

  def derive(password, salt, cost, block_size, parallelization)
    OpenSSL::KDF.scrypt(password, salt: salt, N: cost, r: block_size, p: parallelization, length: KEY_LENGTH)
  end
end
