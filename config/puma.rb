# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["RAILS_WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is 0 (single mode). You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
workers Integer(ENV.fetch("RAILS_WEB_CONCURRENCY", 0))
threads Integer(ENV.fetch("RAILS_MAX_THREADS", 3))

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port Integer(ENV.fetch("RAILS_PORT", 3000))

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["RAILS_PIDFILE"] if ENV["RAILS_PIDFILE"]

if Integer(ENV.fetch("RAILS_WEB_CONCURRENCY", 0)) > 0
  # Tell the Ruby VM that we're finished booting up.
  #
  # Now's the time to tidy the heap (GC, compact, free empty, malloc_trim, etc)
  # for optimal copy-on-write efficiency.
  before_fork do
    Process.warmup
  end

  # Defer major GC (full marking phase) until after request handling,
  # and perform major GC deferred during request handling.
  before_worker_boot do
    GC.config(rgengc_allow_full_mark: false)
  end

  out_of_band do
    GC.start if GC.latest_gc_info(:need_major_by)
  end
end
