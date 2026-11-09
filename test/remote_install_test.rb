# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'

# deploy/remote-install.sh against a fake podman/systemctl and a temporary HOME.
class RemoteInstallTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SCRIPT = File.join(ROOT, 'deploy/remote-install.sh')
  FAKES = File.join(ROOT, 'test/support/deploy')

  def setup
    @home = Dir.mktmpdir('remote-install-home')
    @state = Dir.mktmpdir('remote-install-state')
  end

  def teardown
    FileUtils.rm_rf([@home, @state])
  end

  def run_install(*args, release: 'r1', env: {})
    File.write(File.join(@state, 'next-release'), release)
    archive = File.join(@state, "images-#{release}.tar.gz")
    File.write(archive, 'fake')
    args = [archive] if args.empty?
    Open3.capture2e(base_env.merge('RELEASE' => release).merge(env), SCRIPT, *args)
  end

  def base_env
    { 'HOME' => @home, 'FAKE_PODMAN_STATE' => @state, 'PODMAN' => File.join(FAKES, 'fake_podman'),
      'SYSTEMCTL' => File.join(FAKES, 'fake_systemctl'), 'JOURNALCTL' => File.join(FAKES, 'fake_journalctl'),
      'HEALTH_ATTEMPTS' => '1', 'SKIP_HOST_CHECK' => '1',
      'STOCKFISH_ARCH' => 'x86-64-sse41-popcnt', 'XDG_RUNTIME_DIR' => @state }
  end

  def image(name)
    path = File.join(@state, 'images', name.tr('/:', '__'))
    File.exist?(path) ? File.read(path).strip : nil
  end

  def env_file(name)
    File.read(File.join(@home, '.config/chess-learner', name))
  end

  def env_value(file, key)
    env_file(file)[/^#{key}=(.*)$/, 1]
  end

  def calls
    File.read(File.join(@state, 'calls'))
  end

  def test_first_install_creates_env_files_with_matching_secrets
    output, status = run_install

    assert_predicate status, :success?, output
    token = env_value('stockfish-pool.env', 'API_TOKENS')

    assert_match(/\A\h{64}\z/, token)
    assert_equal token, env_value('chess-learner.env', 'ENGINE_TOKEN')
    assert_match(/OWNER_PASSWORD_HASH is not set/, output)
  end

  def test_first_install_generates_distinct_app_secrets
    run_install
    session = env_value('chess-learner.env', 'SESSION_SECRET')

    assert_match(/\A\h{128}\z/, session)
    refute_equal session, env_value('chess-learner.env', 'ENGINE_SUBJECT_SECRET')
  end

  def test_env_files_are_private
    run_install
    modes = %w[stockfish-pool.env chess-learner.env].map do |name|
      File.stat(File.join(@home, '.config/chess-learner', name)).mode & 0o777
    end

    assert_equal [0o600, 0o600], modes
    assert_equal 0o700, File.stat(File.join(@home, '.config/chess-learner')).mode & 0o777
  end

  def test_installs_units_restarts_services_and_cleans_up
    output, = run_install
    units = Dir.children(File.join(@home, '.config/containers/systemd')).sort

    assert_equal Dir.children(File.join(ROOT, 'deploy/quadlet')).sort, units
    assert_includes calls, 'systemctl daemon-reload'
    assert_includes calls, 'systemctl restart stockfish-pool.service chess-learner.service'
    assert_match(/Release r1 is running/, output)
    refute_path_exists File.join(@state, 'images-r1.tar.gz')
  end

  def test_second_install_keeps_env_files_and_remembers_releases
    run_install(release: 'r1')
    before = env_file('chess-learner.env')
    output, status = run_install(release: 'r2')

    assert_predicate status, :success?, output
    assert_equal before, env_file('chess-learner.env')
    assert_match(/unchanged: chess-learner.container/, output)
    assert_equal 'r2-chess-learner:app', image('localhost/chess-learner:good')
    assert_equal 'r1-chess-learner:app', image('localhost/chess-learner:previous')
  end

  def test_unhealthy_release_is_not_remembered_and_rollback_returns_to_good
    run_install(release: 'r1')
    FileUtils.touch(File.join(@state, 'unhealthy-chess-learner'))
    output, status = run_install(release: 'r2')

    refute_predicate status, :success?
    assert_match(/did not become healthy.*fake journal: app crashed at boot.*--rollback/m, output)
    assert_equal 'r1-chess-learner:app', image('localhost/chess-learner:good')
    FileUtils.rm(File.join(@state, 'unhealthy-chess-learner'))
    output, = run_install('--rollback')

    assert_match(/Rolled back to the :good release/, output)
    assert_equal 'r1-chess-learner:app', image('localhost/chess-learner:app')
  end

  def test_failed_start_shows_the_units_journal
    FileUtils.touch(File.join(@state, 'unhealthy-chess-learner'))
    run_install

    assert_includes calls, 'journalctl -u chess-learner.service -n 40 --no-pager'
  end

  def test_rollback_from_a_healthy_release_goes_to_previous
    run_install(release: 'r1')
    run_install(release: 'r2')
    output, status = run_install('--rollback')

    assert_predicate status, :success?, output
    assert_equal 'r1-chess-learner:app', image('localhost/chess-learner:app')
    assert_equal 'r1-stockfish-pool:latest', image('localhost/stockfish-pool:latest')
    assert_equal 'r2-chess-learner:app', image('localhost/chess-learner:previous'), 'a second rollback undoes this one'
  end

  def test_refuses_when_only_one_env_file_exists
    run_install
    FileUtils.rm(File.join(@home, '.config/chess-learner/stockfish-pool.env'))
    output, status = run_install(release: 'r2')

    refute_predicate status, :success?
    assert_match(/only one of/, output)
  end

  def test_service_names_must_match_the_units
    output, status = run_install(env: { 'FRONTEND_NAME' => 'learner' })

    refute_predicate status, :success?
    assert_match(%r{no deploy/quadlet/learner.container}, output)
  end
end
