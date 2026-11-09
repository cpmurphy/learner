# frozen_string_literal: true

# The engine pool lives in this process, so run a single Puma process (no
# cluster workers). Threads must cover the pool plus both lane queues, or Puma
# would queue requests itself before the pool can answer 429.
threads_count = Integer(ENV.fetch('PUMA_THREADS', 16))
threads threads_count, threads_count
workers 0
port Integer(ENV.fetch('PORT', 4000))
environment ENV.fetch('APP_ENV', 'production')

# Exit 0 after a graceful SIGTERM stop (the default re-raises the signal and the
# process exits 1), so systemd records a planned stop or restart as clean.
raise_exception_on_sigterm false
