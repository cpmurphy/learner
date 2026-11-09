# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/owner_password'

class OwnerPasswordTest < Minitest::Test
  def test_round_trip
    encoded = OwnerPassword.create('correct horse', cost: 2**10)

    assert OwnerPassword.verify('correct horse', encoded)
    refute OwnerPassword.verify('wrong horse', encoded)
    refute OwnerPassword.verify(nil, encoded)
  end

  def test_salts_differ
    refute_equal OwnerPassword.create('same', cost: 2**10), OwnerPassword.create('same', cost: 2**10)
  end

  def test_default_cost_is_used_and_recorded
    assert_match(/\Ascrypt\$16384\$8\$1\$/, OwnerPassword.create('pw'))
  end

  def test_malformed_values_never_verify
    ['', 'plaintext', 'scrypt$1$2$3', 'scrypt$x$8$1$AAAA$AAAA', 'bcrypt$a$b$c$d$e'].each do |encoded|
      refute OwnerPassword.verify('pw', encoded), encoded
    end
  end

  def test_validate
    assert OwnerPassword.validate!(OwnerPassword.create('pw', cost: 2**10))
    assert_raises(ArgumentError) { OwnerPassword.validate!('hunter2') }
  end
end
